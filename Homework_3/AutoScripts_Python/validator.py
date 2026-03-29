"""
validator.py — Module kiểm tra và xác thực cấu hình mạng
==========================================================
Mô-đun này chịu trách nhiệm:
  1. Kiểm tra cấu hình IP thực tế trên thiết bị
  2. So sánh cấu hình mong muốn (inventory) vs thực tế (device)
  3. Phát hiện sai lệch (misconfiguration)
  4. Kiểm tra OSPF neighbor adjacency
  5. Trả về báo cáo validation chi tiết
"""

import logging
import re
import ipaddress
from config_deployer import execute_on_device

logger = logging.getLogger(__name__)


# ==============================================================
# PHẦN 1: THU THẬP THÔNG TIN TỪ THIẾT BỊ
# ==============================================================

def get_interface_ips(container_name: str) -> dict:
    """
    Thu thập IP thực tế trên thiết bị bằng 'ip addr show'.

    Trả về:
        Dict {interface_name: [list_of_ips]}
        Ví dụ: {'eth1': ['10.1.1.2/30'], 'lo': ['10.0.1.1/32']}
    """
    output = execute_on_device(container_name, "ip -4 addr show")
    if not output:
        return {}

    interfaces = {}
    current_intf = None

    for line in output.splitlines():
        # Detect interface name: "2: eth1@..."
        intf_match = re.match(r'\d+:\s+(\S+?)[@:]', line)
        if intf_match:
            current_intf = intf_match.group(1)
            interfaces.setdefault(current_intf, [])

        # Detect IP: "    inet 10.1.1.2/30 ..."
        ip_match = re.search(r'inet\s+(\d+\.\d+\.\d+\.\d+/\d+)', line)
        if ip_match and current_intf:
            interfaces[current_intf].append(ip_match.group(1))

    return interfaces


def get_ospf_neighbors(container_name: str) -> list[dict]:
    """
    Thu thập danh sách OSPF neighbors bằng vtysh.

    Trả về:
        List of dict: [{neighbor_id, state, interface}, ...]
    """
    output = execute_on_device(
        container_name,
        'vtysh -c "show ip ospf neighbor"'
    )
    if not output:
        return []

    neighbors = []
    for line in output.splitlines():
        # Parse: "10.0.1.1  1  Full/DROther  10.1.1.1  eth1:10.1.1.2"
        parts = line.split()
        if len(parts) >= 5 and re.match(r'\d+\.\d+\.\d+\.\d+', parts[0]):
            neighbors.append({
                "neighbor_id": parts[0],
                "state": parts[2] if len(parts) > 2 else "unknown",
                "interface": parts[-1] if len(parts) > 4 else "unknown",
            })

    return neighbors


def get_routing_table(container_name: str) -> str:
    """Thu thập bảng định tuyến."""
    output = execute_on_device(
        container_name,
        'vtysh -c "show ip route"'
    )
    return output or ""


# ==============================================================
# PHẦN 2: SO SÁNH VÀ XÁC THỰC
# ==============================================================

def validate_device_config(device_name: str, device_info: dict,
                           lab_name: str = "clos02-light") -> dict:
    """
    Xác thực cấu hình của MỘT thiết bị.

    Quy trình:
      1. Lấy IP thực tế từ thiết bị
      2. So sánh với IP mong muốn trong inventory
      3. Kiểm tra OSPF neighbors (nếu là FRR device)
      4. Trả về báo cáo chi tiết

    Trả về:
        Dict {
            'device': device_name,
            'status': 'PASS' hoặc 'FAIL',
            'checks': [list of check results],
            'misconfigs': [list of misconfigurations]
        }
    """
    container = f"clab-{lab_name}-{device_name}"
    role = device_info.get("role", "")
    report = {
        "device": device_name,
        "role": role,
        "status": "PASS",
        "checks": [],
        "misconfigs": [],
    }

    logger.info(f"[{device_name}] Bắt đầu validation...")

    # --- Check 1: Interface IP ---
    actual_ips = get_interface_ips(container)
    expected_interfaces = device_info.get("interfaces", {})

    for intf_name, intf_info in expected_interfaces.items():
        expected_ip = intf_info.get("ip")
        if not expected_ip:
            continue

        actual_ip_list = actual_ips.get(intf_name, [])

        if expected_ip in actual_ip_list:
            report["checks"].append({
                "check": f"IP {intf_name}",
                "expected": expected_ip,
                "actual": expected_ip,
                "result": "PASS",
            })
        else:
            report["checks"].append({
                "check": f"IP {intf_name}",
                "expected": expected_ip,
                "actual": actual_ip_list if actual_ip_list else "Không có IP",
                "result": "FAIL",
            })
            report["misconfigs"].append(
                f"{intf_name}: Mong muốn {expected_ip}, thực tế {actual_ip_list}"
            )
            report["status"] = "FAIL"

    # --- Check 2: Loopback IP ---
    expected_lo = device_info.get("loopback")
    if expected_lo:
        actual_lo = actual_ips.get("lo", [])
        if expected_lo in actual_lo:
            report["checks"].append({
                "check": "Loopback IP",
                "expected": expected_lo,
                "actual": expected_lo,
                "result": "PASS",
            })
        else:
            report["checks"].append({
                "check": "Loopback IP",
                "expected": expected_lo,
                "actual": actual_lo,
                "result": "FAIL",
            })
            report["misconfigs"].append(
                f"Loopback: Mong muốn {expected_lo}, thực tế {actual_lo}"
            )
            report["status"] = "FAIL"

    # --- Check 3: OSPF Neighbors (chỉ cho FRR devices) ---
    if role in ("superspine", "spine", "leaf"):
        neighbors = get_ospf_neighbors(container)
        expected_peer_count = len([
            i for i in expected_interfaces.values()
            if i.get("peer") and not i["peer"].startswith("client")
        ])

        full_neighbors = [n for n in neighbors if "Full" in n.get("state", "")]

        report["checks"].append({
            "check": "OSPF Neighbors",
            "expected": f"{expected_peer_count} peers (Full state)",
            "actual": f"{len(full_neighbors)} neighbors in Full state",
            "result": "PASS" if len(full_neighbors) >= expected_peer_count else "WARN",
        })

        if len(full_neighbors) < expected_peer_count:
            report["misconfigs"].append(
                f"OSPF: Chỉ {len(full_neighbors)}/{expected_peer_count} "
                f"neighbors ở trạng thái Full"
            )

    return report


def validate_all(inventory: dict, lab_name: str = "clos02-light") -> list[dict]:
    """
    Xác thực TẤT CẢ thiết bị trong inventory.

    Trả về:
        List of validation reports
    """
    devices = inventory.get("devices", {})
    reports = []

    for device_name, device_info in devices.items():
        report = validate_device_config(device_name, device_info, lab_name)
        reports.append(report)

    # Tóm tắt
    passed = sum(1 for r in reports if r["status"] == "PASS")
    total = len(reports)
    logger.info(f"\n{'='*50}")
    logger.info(f"VALIDATION: {passed}/{total} thiết bị PASS")
    logger.info(f"{'='*50}")

    return reports


def print_validation_report(reports: list[dict]) -> None:
    """In báo cáo validation ra console theo dạng bảng."""
    print("\n" + "=" * 70)
    print(f"  {'THIẾT BỊ':<16} {'VAI TRÒ':<12} {'KẾT QUẢ':<10} {'SAI LỆCH'}")
    print("=" * 70)

    for r in reports:
        misconfig_str = "; ".join(r["misconfigs"]) if r["misconfigs"] else "Không có"
        status_icon = "✅" if r["status"] == "PASS" else "❌"
        print(
            f"  {r['device']:<16} {r['role']:<12} "
            f"{status_icon} {r['status']:<6} {misconfig_str}"
        )

    print("=" * 70)

    passed = sum(1 for r in reports if r["status"] == "PASS")
    print(f"  Tổng kết: {passed}/{len(reports)} PASS\n")


# ===== CHẠY ĐỘC LẬP =====
if __name__ == "__main__":
    from inventory_loader import load_inventory

    logging.basicConfig(level=logging.INFO)
    inv = load_inventory()

    print("\n[DRY RUN] Validation sẽ chạy khi topology đang hoạt động.")
    print("Các check sẽ thực hiện:")
    for name, info in inv["devices"].items():
        intfs = list(info.get("interfaces", {}).keys())
        print(f"  {name}: kiểm tra {len(intfs)} interfaces")
