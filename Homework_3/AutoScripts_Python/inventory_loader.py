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
    return inventory.get("devices", {})


def get_devices_by_role(inventory: dict, role: str) -> dict:
    devices = get_devices(inventory)
    return {
        name: info
        for name, info in devices.items()
        if info.get("role") == role
    }


def get_devices_by_pod(inventory: dict, pod: int) -> dict:
    devices = get_devices(inventory)
    return {
        name: info
        for name, info in devices.items()
        if info.get("pod") == pod
    }


def get_frr_devices(inventory: dict) -> dict:
    devices = get_devices(inventory)
    return {
        name: info
        for name, info in devices.items()
        if info.get("device_type") == "linux"
    }


def print_inventory_summary(inventory: dict) -> None:
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
