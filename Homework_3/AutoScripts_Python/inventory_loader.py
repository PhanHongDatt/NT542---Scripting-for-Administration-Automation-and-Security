"""
inventory_loader.py — Module đọc và phân tích Network Inventory
================================================================
Mô-đun này chịu trách nhiệm:
  1. Đọc file inventory YAML
  2. Parse thông tin thiết bị
  3. Lấy credentials an toàn từ biến môi trường
  4. Cung cấp hàm truy vấn (filter theo role, pod, tier)
"""

import os
import sys
import yaml
import logging

logger = logging.getLogger(__name__)


def load_inventory(filepath: str = "inventory.yml") -> dict:
    """
    Đọc file inventory YAML và trả về dict chứa toàn bộ thông tin.

    Tham số:
        filepath: Đường dẫn tới file inventory (mặc định: inventory.yml)

    Trả về:
        dict chứa 'credentials' và 'devices'

    Ngoại lệ:
        FileNotFoundError: Nếu file không tồn tại
        yaml.YAMLError: Nếu YAML không hợp lệ
    """
    if not os.path.exists(filepath):
        logger.error(f"Không tìm thấy file inventory: {filepath}")
        raise FileNotFoundError(f"File inventory không tồn tại: {filepath}")

    with open(filepath, "r", encoding="utf-8") as f:
        try:
            inventory = yaml.safe_load(f)
            logger.info(f"Đã load inventory từ {filepath}: {len(inventory.get('devices', {}))} thiết bị")
            return inventory
        except yaml.YAMLError as e:
            logger.error(f"Lỗi parse YAML: {e}")
            raise


def get_credentials(inventory: dict) -> dict:
    """
    Lấy credentials từ inventory, ưu tiên biến môi trường.

    BẢO MẬT: Password KHÔNG được hardcode trong file.
    Nếu trường 'password_env' tồn tại, hàm sẽ đọc giá trị
    từ biến môi trường tương ứng.

    Trả về:
        dict với keys: username, password, ssh_port
    """
    creds = inventory.get("credentials", {}).get("default", {})
    username = creds.get("username", "admin")
    ssh_port = creds.get("ssh_port", 22)

    # Đọc password từ biến môi trường
    password_env = creds.get("password_env", "NETWORK_PASSWORD")
    password = os.environ.get(password_env, "")

    if not password:
        logger.warning(
            f"Biến môi trường '{password_env}' chưa được set. "
            f"Hãy chạy: export {password_env}='your_password'"
        )

    return {
        "username": username,
        "password": password,
        "ssh_port": ssh_port,
    }


def get_devices(inventory: dict) -> dict:
    """Trả về dict tất cả thiết bị."""
    return inventory.get("devices", {})


def get_devices_by_role(inventory: dict, role: str) -> dict:
    """
    Lọc thiết bị theo vai trò (role).

    Tham số:
        role: 'superspine', 'spine', 'leaf', hoặc 'client'

    Ví dụ:
        spines = get_devices_by_role(inv, 'spine')
        # Trả về dict chỉ chứa các spine switch
    """
    devices = get_devices(inventory)
    return {
        name: info
        for name, info in devices.items()
        if info.get("role") == role
    }


def get_devices_by_pod(inventory: dict, pod: int) -> dict:
    """Lọc thiết bị theo POD (1, 2, hoặc 3)."""
    devices = get_devices(inventory)
    return {
        name: info
        for name, info in devices.items()
        if info.get("pod") == pod
    }


def get_frr_devices(inventory: dict) -> dict:
    """
    Trả về các thiết bị chạy FRRouting (loại 'linux'),
    tức là superspine + spine + leaf (KHÔNG bao gồm client).
    """
    devices = get_devices(inventory)
    return {
        name: info
        for name, info in devices.items()
        if info.get("device_type") == "linux"
    }


def print_inventory_summary(inventory: dict) -> None:
    """In tóm tắt inventory ra console."""
    devices = get_devices(inventory)
    roles = {}
    for name, info in devices.items():
        role = info.get("role", "unknown")
        roles.setdefault(role, []).append(name)

    print("=" * 60)
    print("       NETWORK INVENTORY SUMMARY")
    print("=" * 60)
    for role in ["superspine", "spine", "leaf", "client"]:
        members = roles.get(role, [])
        print(f"  {role.upper():12s}: {len(members):2d} thiết bị — {', '.join(members)}")
    print(f"  {'TỔNG CỘNG':12s}: {len(devices):2d} thiết bị")
    print("=" * 60)


# ===== CHẠY ĐỘC LẬP ĐỂ KIỂM TRA =====
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    inv = load_inventory()
    print_inventory_summary(inv)

    creds = get_credentials(inv)
    print(f"\nCredentials: user={creds['username']}, port={creds['ssh_port']}")
    print(f"Password set: {'Có' if creds['password'] else 'Chưa (cần export biến môi trường)'}")
