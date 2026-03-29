"""
monitor.py — Module giám sát trạng thái mạng
==============================================
Mô-đun này chịu trách nhiệm:
  1. Kiểm tra trạng thái thiết bị (up/down)
  2. Kiểm tra trạng thái interface
  3. Kiểm tra bảng định tuyến
  4. Thực hiện ping test (end-to-end connectivity)
  5. Tạo báo cáo monitoring tổng hợp
"""

import logging
import re
import time
from datetime import datetime
from config_deployer import execute_on_device

logger = logging.getLogger(__name__)


# ==============================================================
# PHẦN 1: KIỂM TRA TRẠNG THÁI THIẾT BỊ
# ==============================================================

def check_device_status(container_name: str) -> dict:
    """
    Kiểm tra thiết bị có đang hoạt động không.

    Logic:
      - Chạy 'echo OK' trên container
      - Nếu trả về 'OK' → thiết bị UP
      - Nếu timeout/lỗi → thiết bị DOWN

    Trả về:
        {'status': 'UP'/'DOWN', 'response_time_ms': float}
    """
    start = time.time()
    result = execute_on_device(container_name, "echo OK", timeout=10)
    elapsed = (time.time() - start) * 1000  # ms

    if result and "OK" in result:
        return {"status": "UP", "response_time_ms": round(elapsed, 1)}
    else:
        return {"status": "DOWN", "response_time_ms": None}


def check_all_devices_status(inventory: dict,
                              lab_name: str = "clos02-light") -> list[dict]:
    """
    Kiểm tra trạng thái tất cả thiết bị.

    Trả về:
        List of {'device': name, 'status': 'UP'/'DOWN', ...}
    """
    devices = inventory.get("devices", {})
    results = []

    for device_name, device_info in devices.items():
        container = f"clab-{lab_name}-{device_name}"
        status = check_device_status(container)
        results.append({
            "device": device_name,
            "role": device_info.get("role", ""),
            **status,
        })

    return results


# ==============================================================
# PHẦN 2: KIỂM TRA INTERFACE
# ==============================================================

def check_interface_status(container_name: str) -> list[dict]:
    """
    Kiểm tra trạng thái tất cả interface trên thiết bị.

    Sử dụng lệnh 'ip link show' để lấy:
      - Tên interface
      - Trạng thái (UP/DOWN)
      - MAC address

    Trả về:
        List of {'interface': name, 'state': 'UP'/'DOWN', 'mac': str}
    """
    output = execute_on_device(container_name, "ip link show")
    if not output:
        return []

    interfaces = []
    for line in output.splitlines():
        # Match: "2: eth1@... <BROADCAST,...,UP,...> ..."
        match = re.match(
            r'\d+:\s+(\S+?)[@:].*<([^>]+)>',
            line
        )
        if match:
            intf_name = match.group(1)
            flags = match.group(2)
            state = "UP" if "UP" in flags and "NO-CARRIER" not in flags else "DOWN"
            interfaces.append({
                "interface": intf_name,
                "state": state,
            })

    return interfaces


# ==============================================================
# PHẦN 3: KIỂM TRA ROUTING
# ==============================================================

def check_routing_table(container_name: str) -> dict:
    """
    Thu thập và phân tích bảng định tuyến.

    Trả về:
        {
            'total_routes': int,
            'ospf_routes': int,
            'connected_routes': int,
            'raw_output': str
        }
    """
    output = execute_on_device(
        container_name,
        'vtysh -c "show ip route summary"'
    )

    result = {
        "total_routes": 0,
        "ospf_routes": 0,
        "connected_routes": 0,
        "raw_output": output or "",
    }

    if not output:
        return result

    for line in output.splitlines():
        if "ospf" in line.lower():
            nums = re.findall(r'\d+', line)
            if nums:
                result["ospf_routes"] = int(nums[0])
        elif "connected" in line.lower():
            nums = re.findall(r'\d+', line)
            if nums:
                result["connected_routes"] = int(nums[0])
        elif "total" in line.lower() or "fib" in line.lower():
            nums = re.findall(r'\d+', line)
            if nums:
                result["total_routes"] = int(nums[-1])

    return result


# ==============================================================
# PHẦN 4: PING TEST (END-TO-END CONNECTIVITY)
# ==============================================================

def ping_test(container_name: str, target_ip: str,
              count: int = 3, timeout: int = 5) -> dict:
    """
    Thực hiện ping test từ container tới target IP.

    Tham số:
        container_name: Container nguồn
        target_ip: IP đích
        count: Số gói tin ping
        timeout: Timeout mỗi gói (giây)

    Trả về:
        {
            'target': target_ip,
            'success': bool,
            'packets_sent': int,
            'packets_received': int,
            'packet_loss': str,
            'avg_rtt_ms': float or None,
        }
    """
    output = execute_on_device(
        container_name,
        f"ping -c {count} -W {timeout} {target_ip}",
        timeout=count * timeout + 10
    )

    result = {
        "target": target_ip,
        "success": False,
        "packets_sent": count,
        "packets_received": 0,
        "packet_loss": "100%",
        "avg_rtt_ms": None,
    }

    if not output:
        return result

    # Parse packet loss: "3 packets transmitted, 3 received, 0% packet loss"
    loss_match = re.search(
        r'(\d+)\s+packets?\s+transmitted.*?(\d+)\s+received.*?(\d+)%\s+packet\s+loss',
        output
    )
    if loss_match:
        result["packets_sent"] = int(loss_match.group(1))
        result["packets_received"] = int(loss_match.group(2))
        result["packet_loss"] = f"{loss_match.group(3)}%"
        result["success"] = int(loss_match.group(3)) < 100

    # Parse RTT: "rtt min/avg/max/mdev = 0.123/0.456/0.789/0.111 ms"
    rtt_match = re.search(r'rtt.*?=\s*[\d.]+/([\d.]+)/', output)
    if rtt_match:
        result["avg_rtt_ms"] = float(rtt_match.group(1))

    return result


def run_connectivity_matrix(inventory: dict,
                             lab_name: str = "clos02-light") -> list[dict]:
    """
    Chạy ping test giữa TẤT CẢ client hosts.

    Logic:
      - Lấy danh sách tất cả client
      - Từ mỗi client, ping tới mọi client khác
      - Trả về ma trận kết nối

    Đây là test end-to-end quan trọng nhất:
    nếu client1 ping được client6, toàn bộ CLOS fabric hoạt động đúng.
    """
    devices = inventory.get("devices", {})
    clients = {
        name: info for name, info in devices.items()
        if info.get("role") == "client"
    }

    # Lấy IP của tất cả client
    client_ips = {}
    for name, info in clients.items():
        for intf_info in info.get("interfaces", {}).values():
            ip = intf_info.get("ip", "")
            if ip:
                client_ips[name] = ip.split("/")[0]
                break

    results = []

    for src_name in sorted(client_ips.keys()):
        src_container = f"clab-{lab_name}-{src_name}"
        for dst_name in sorted(client_ips.keys()):
            if src_name == dst_name:
                continue

            dst_ip = client_ips[dst_name]
            ping_result = ping_test(src_container, dst_ip)
            results.append({
                "source": src_name,
                "destination": dst_name,
                **ping_result,
            })

    return results


# ==============================================================
# PHẦN 5: BÁO CÁO TỔNG HỢP
# ==============================================================

def run_full_monitoring(inventory: dict,
                         lab_name: str = "clos02-light") -> dict:
    """
    Chạy toàn bộ monitoring suite và trả về báo cáo tổng hợp.

    Bao gồm:
      1. Device status (up/down)
      2. Interface status
      3. Routing table summary
      4. Connectivity matrix (client-to-client ping)
    """
    report = {
        "timestamp": datetime.now().isoformat(),
        "lab_name": lab_name,
        "device_status": [],
        "interface_status": {},
        "routing_summary": {},
        "connectivity": [],
    }

    logger.info("=" * 60)
    logger.info("  BẮT ĐẦU MONITORING SUITE")
    logger.info("=" * 60)

    # 1. Device Status
    logger.info("\n[1/4] Kiểm tra trạng thái thiết bị...")
    report["device_status"] = check_all_devices_status(inventory, lab_name)

    # 2. Interface Status (chỉ cho FRR devices)
    logger.info("\n[2/4] Kiểm tra interface...")
    devices = inventory.get("devices", {})
    for name, info in devices.items():
        if info.get("role") in ("superspine", "spine", "leaf"):
            container = f"clab-{lab_name}-{name}"
            report["interface_status"][name] = check_interface_status(container)

    # 3. Routing Summary (chỉ cho FRR devices)
    logger.info("\n[3/4] Kiểm tra bảng định tuyến...")
    for name, info in devices.items():
        if info.get("role") in ("superspine", "spine", "leaf"):
            container = f"clab-{lab_name}-{name}"
            report["routing_summary"][name] = check_routing_table(container)

    # 4. Connectivity Matrix
    logger.info("\n[4/4] Chạy ping test giữa các client...")
    report["connectivity"] = run_connectivity_matrix(inventory, lab_name)

    return report


def print_monitoring_report(report: dict) -> None:
    """In báo cáo monitoring ra console."""
    print(f"\n{'='*70}")
    print(f"  MONITORING REPORT — {report['timestamp']}")
    print(f"  Lab: {report['lab_name']}")
    print(f"{'='*70}")

    # Device status
    print(f"\n  [DEVICE STATUS]")
    print(f"  {'Thiết bị':<16} {'Vai trò':<12} {'Trạng thái':<10} {'Response (ms)'}")
    print(f"  {'-'*55}")
    for d in report["device_status"]:
        rt = f"{d['response_time_ms']:.1f}" if d["response_time_ms"] else "N/A"
        icon = "🟢" if d["status"] == "UP" else "🔴"
        print(f"  {d['device']:<16} {d['role']:<12} {icon} {d['status']:<6} {rt}")

    # Connectivity
    if report["connectivity"]:
        print(f"\n  [CONNECTIVITY — Client-to-Client Ping]")
        print(f"  {'Nguồn':<10} {'Đích':<10} {'Kết quả':<10} {'Loss':<8} {'RTT (ms)'}")
        print(f"  {'-'*50}")
        for c in report["connectivity"]:
            icon = "✅" if c["success"] else "❌"
            rtt = f"{c['avg_rtt_ms']:.2f}" if c["avg_rtt_ms"] else "N/A"
            print(
                f"  {c['source']:<10} {c['destination']:<10} "
                f"{icon} {'OK':<6} {c['packet_loss']:<8} {rtt}"
            )

    print(f"\n{'='*70}\n")


# ===== CHẠY ĐỘC LẬP =====
if __name__ == "__main__":
    from inventory_loader import load_inventory

    logging.basicConfig(level=logging.INFO)
    inv = load_inventory()

    print("\n[DRY RUN] Monitoring sẽ chạy khi topology đang hoạt động.")
    print("Các bài test sẽ thực hiện:")
    print("  1. Device status check (21 thiết bị)")
    print("  2. Interface status (15 FRR devices)")
    print("  3. Routing table summary (15 FRR devices)")
    print("  4. Connectivity matrix (6 clients × 5 targets = 30 ping tests)")
