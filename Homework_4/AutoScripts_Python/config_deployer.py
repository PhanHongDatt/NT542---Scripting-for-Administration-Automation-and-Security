"""
config_deployer.py — Module triển khai cấu hình mạng
=====================================================
Mô-đun này chịu trách nhiệm:
  1. Sinh cấu hình (FRRouting CLI) từ inventory
  2. Đẩy cấu hình tới thiết bị qua SSH (docker exec)
  3. Cấu hình client hosts (ip addr, route)
  4. Ghi log mọi hành động

Lưu ý: Trong môi trường Containerlab, các node là container Docker.
Ta dùng 'docker exec' thay vì SSH trực tiếp cho đơn giản.
"""

import subprocess
import logging
import ipaddress
from typing import Optional

logger = logging.getLogger(__name__)


# ==============================================================
# PHẦN 1: SINH CẤU HÌNH FRRouting (vtysh)
# ==============================================================

def generate_frr_config(device_name: str, device_info: dict) -> list[str]:
    """
    Sinh danh sách lệnh FRRouting (vtysh) cho một thiết bị.

    Logic:
      1. Đặt hostname
      2. Cấu hình loopback interface
      3. Cấu hình IP cho từng interface P2P
      4. Bật OSPF trên tất cả interface (sử dụng area 0)

    Tham số:
        device_name: Tên thiết bị (ví dụ: 'spine1')
        device_info: Dict thông tin từ inventory

    Trả về:
        List các lệnh vtysh
    """
    commands = []

    # --- Bước 1: Hostname ---
    commands.append(f"hostname {device_name}")

    # --- Bước 2: Loopback ---
    loopback = device_info.get("loopback")
    if loopback:
        commands.extend([
            "interface lo",
            f"  ip address {loopback}",
            "exit",
        ])

    # --- Bước 3: Interface IP ---
    interfaces = device_info.get("interfaces", {})
    for intf_name, intf_info in interfaces.items():
        ip = intf_info.get("ip")
        if ip:
            commands.extend([
                f"interface {intf_name}",
                f"  ip address {ip}",
                "  no shutdown",
                "exit",
            ])

    # --- Bước 4: OSPF ---
    commands.extend([
        "router ospf",
        f"  ospf router-id {loopback.split('/')[0]}" if loopback else "  ospf router-id 1.1.1.1",
    ])

    # Quảng bá tất cả mạng vào OSPF area 0
    if loopback:
        net = ipaddress.ip_network(loopback, strict=False)
        commands.append(f"  network {net.network_address}/{net.prefixlen} area 0")

    for intf_name, intf_info in interfaces.items():
        ip = intf_info.get("ip")
        if ip:
            net = ipaddress.ip_network(ip, strict=False)
            commands.append(f"  network {net.network_address}/{net.prefixlen} area 0")

    commands.append("exit")

    return commands


def generate_client_config(device_name: str, device_info: dict) -> list[str]:
    """
    Sinh lệnh Linux cho client host.

    Logic:
      1. Gán IP cho interface eth1
      2. Thêm default gateway

    Trả về:
        List các lệnh shell
    """
    commands = []
    interfaces = device_info.get("interfaces", {})

    for intf_name, intf_info in interfaces.items():
        ip = intf_info.get("ip")
        if ip:
            commands.append(f"ip addr add {ip} dev {intf_name} 2>/dev/null || true")
            commands.append(f"ip link set {intf_name} up")

    default_gw = device_info.get("default_gw")
    if default_gw:
        commands.append(f"ip route add default via {default_gw} 2>/dev/null || true")

    return commands


# ==============================================================
# PHẦN 2: THỰC THI CẤU HÌNH QUA DOCKER EXEC
# ==============================================================

def execute_on_device(container_name: str, command: str,
                      timeout: int = 30) -> Optional[str]:
    """
    Chạy lệnh trên container Containerlab qua docker exec.

    Tham số:
        container_name: Tên container (ví dụ: clab-clos02-light-spine1)
        command: Lệnh cần chạy
        timeout: Timeout tính bằng giây

    Trả về:
        stdout nếu thành công, None nếu lỗi
    """
    full_cmd = ["docker", "exec", container_name, "sh", "-c", command]

    try:
        result = subprocess.run(
            full_cmd,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        if result.returncode != 0:
            logger.warning(
                f"[{container_name}] Lệnh thất bại (rc={result.returncode}): "
                f"{result.stderr.strip()}"
            )
            return None

        logger.debug(f"[{container_name}] OK: {command[:60]}...")
        return result.stdout

    except subprocess.TimeoutExpired:
        logger.error(f"[{container_name}] Timeout sau {timeout}s: {command[:60]}")
        return None
    except FileNotFoundError:
        logger.error("Docker CLI không tìm thấy. Hãy cài Docker.")
        return None


def deploy_frr_config(device_name: str, device_info: dict,
                      lab_name: str = "clos02-light") -> bool:
    """
    Đẩy cấu hình FRRouting tới một thiết bị.

    Quy trình:
      1. Sinh danh sách lệnh cấu hình
      2. Ghép thành chuỗi vtysh -c "configure terminal" ...
      3. Thực thi qua docker exec
      4. Lưu cấu hình (write memory)

    Trả về:
        True nếu thành công, False nếu lỗi
    """
    container = f"clab-{lab_name}-{device_name}"
    logger.info(f"[{device_name}] Bắt đầu deploy cấu hình FRR...")

    # Sinh lệnh
    config_commands = generate_frr_config(device_name, device_info)

    # Ghép thành một chuỗi vtysh
    vtysh_input = "configure terminal\n"
    vtysh_input += "\n".join(config_commands)
    vtysh_input += "\nend\nwrite memory\n"

    # Thực thi
    result = execute_on_device(
        container,
        f'echo "{vtysh_input}" | vtysh'
    )

    if result is not None:
        logger.info(f"[{device_name}] Deploy thành công!")
        return True
    else:
        logger.error(f"[{device_name}] Deploy thất bại!")
        return False


def deploy_client_config(device_name: str, device_info: dict,
                         lab_name: str = "clos02-light") -> bool:
    """
    Đẩy cấu hình IP cho client host.

    Trả về:
        True nếu thành công, False nếu lỗi
    """
    container = f"clab-{lab_name}-{device_name}"
    logger.info(f"[{device_name}] Cấu hình client host...")

    commands = generate_client_config(device_name, device_info)
    all_ok = True

    for cmd in commands:
        result = execute_on_device(container, cmd)
        if result is None:
            all_ok = False

    if all_ok:
        logger.info(f"[{device_name}] Cấu hình client OK!")
    else:
        logger.warning(f"[{device_name}] Có lỗi khi cấu hình client.")

    return all_ok


def deploy_all(inventory: dict, lab_name: str = "clos02-light") -> dict:
    """
    Triển khai cấu hình cho TẤT CẢ thiết bị trong inventory.

    Quy trình:
      1. Deploy FRR config cho superspine, spine, leaf (theo thứ tự tier)
      2. Deploy client config cho các host

    Trả về:
        Dict {device_name: True/False} cho từng thiết bị
    """
    devices = inventory.get("devices", {})
    results = {}

    # Sắp xếp: superspine → spine → leaf → client
    tier_order = {"superspine": 0, "spine": 1, "leaf": 2, "client": 3}
    sorted_devices = sorted(
        devices.items(),
        key=lambda x: tier_order.get(x[1].get("role", ""), 99)
    )

    for device_name, device_info in sorted_devices:
        role = device_info.get("role", "")

        if role in ("superspine", "spine", "leaf"):
            results[device_name] = deploy_frr_config(
                device_name, device_info, lab_name
            )
        elif role == "client":
            results[device_name] = deploy_client_config(
                device_name, device_info, lab_name
            )

    # Tóm tắt kết quả
    success = sum(1 for v in results.values() if v)
    total = len(results)
    logger.info(f"\n{'='*50}")
    logger.info(f"KẾT QUẢ DEPLOY: {success}/{total} thiết bị thành công")
    logger.info(f"{'='*50}")

    return results


# ===== CHẠY ĐỘC LẬP ĐỂ XEM CẤU HÌNH MẪU =====
if __name__ == "__main__":
    from inventory_loader import load_inventory

    logging.basicConfig(level=logging.INFO)
    inv = load_inventory()

    # In cấu hình mẫu cho spine1
    print("\n===== CẤU HÌNH MẪU: spine1 =====")
    cmds = generate_frr_config("spine1", inv["devices"]["spine1"])
    for cmd in cmds:
        print(f"  {cmd}")

    # In cấu hình mẫu cho client1
    print("\n===== CẤU HÌNH MẪU: client1 =====")
    cmds = generate_client_config("client1", inv["devices"]["client1"])
    for cmd in cmds:
        print(f"  {cmd}")
