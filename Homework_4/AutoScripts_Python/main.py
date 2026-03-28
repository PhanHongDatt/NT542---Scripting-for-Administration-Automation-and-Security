#!/usr/bin/env python3
"""
main.py — Điểm vào chính của hệ thống tự động hóa mạng CLOS
==============================================================

Chương trình cung cấp giao diện CLI để thực hiện:
  1. Xem inventory
  2. Triển khai cấu hình (deploy)
  3. Xác thực cấu hình (validate)
  4. Giám sát mạng (monitor)
  5. Chạy tất cả tuần tự

Cách sử dụng:
  python main.py inventory     — Xem tóm tắt inventory
  python main.py deploy        — Đẩy cấu hình tới tất cả thiết bị
  python main.py validate      — Kiểm tra cấu hình
  python main.py monitor       — Giám sát trạng thái mạng
  python main.py all           — Chạy deploy → validate → monitor
  python main.py show-config   — In cấu hình mẫu (dry run)
"""

import sys
import os
import logging
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from inventory_loader import (
    load_inventory,
    print_inventory_summary,
    get_credentials,
    get_frr_devices,
)
from config_deployer import (
    deploy_all,
    generate_frr_config,
    generate_client_config,
)
from validator import (
    validate_all,
    print_validation_report,
)
from monitor import (
    run_full_monitoring,
    print_monitoring_report,
)


def setup_logging(log_level: str = "INFO") -> None:
    log_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
    os.makedirs(log_dir, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = os.path.join(log_dir, f"automation_{timestamp}.log")

    logging.basicConfig(
        level=getattr(logging, log_level.upper(), logging.INFO),
        format="%(asctime)s [%(levelname)-5s] %(name)-20s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler(log_file, encoding="utf-8"),
        ],
    )

    logging.info(f"Log file: {log_file}")


LAB_NAME = "clos02-light"
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INVENTORY_FILE = os.path.join(_SCRIPT_DIR, "inventory.yml")


def cmd_inventory():
    inv = load_inventory(INVENTORY_FILE)
    print_inventory_summary(inv)
    creds = get_credentials(inv)
    print(f"\n  Credentials: user={creds['username']}, SSH port={creds['ssh_port']}")
    print(f"  Password env var: {'SET' if creds['password'] else 'NOT SET'}")


def cmd_show_config():
    inv = load_inventory(INVENTORY_FILE)
    devices = inv.get("devices", {})

    samples = {
        "superspine": "superspine1",
        "spine": "spine1",
        "leaf": "leaf1",
        "client": "client1",
    }

    for role, device_name in samples.items():
        if device_name not in devices:
            continue

        device_info = devices[device_name]
        print(f"\n{'='*60}")
        print(f"  SAMPLE CONFIG: {device_name} (role: {role})")
        print(f"{'='*60}")

        if role in ("superspine", "spine", "leaf"):
            cmds = generate_frr_config(device_name, device_info)
            print("  ! --- vtysh Commands (FRRouting) ---")
            for cmd in cmds:
                print(f"  {cmd}")
        elif role == "client":
            cmds = generate_client_config(device_name, device_info)
            print("  # --- Shell Commands (Linux) ---")
            for cmd in cmds:
                print(f"  {cmd}")


def cmd_deploy():
    inv = load_inventory(INVENTORY_FILE)
    print("\nStarting configuration deployment...")
    results = deploy_all(inv, LAB_NAME)

    print(f"\n{'='*50}")
    print(f"  DEPLOYMENT RESULTS")
    print(f"{'='*50}")
    for device, success in results.items():
        status = "SUCCESS" if success else "FAILED"
        print(f"  [{status}] {device}")

    success_count = sum(1 for v in results.values() if v)
    print(f"\n  Total: {success_count}/{len(results)} successful")


def cmd_validate():
    inv = load_inventory(INVENTORY_FILE)
    print("\nStarting configuration validation...")
    reports = validate_all(inv, LAB_NAME)
    print_validation_report(reports)


def cmd_monitor():
    inv = load_inventory(INVENTORY_FILE)
    print("\nStarting network monitoring...")
    report = run_full_monitoring(inv, LAB_NAME)
    print_monitoring_report(report)


def cmd_all():
    print("\n" + "=" * 60)
    print("  RUNNING FULL AUTOMATION PIPELINE")
    print("=" * 60)

    cmd_deploy()
    print("\nWaiting 5 seconds for OSPF convergence...")
    import time
    time.sleep(5)
    cmd_validate()
    cmd_monitor()


COMMANDS = {
    "inventory":   ("View inventory",              cmd_inventory),
    "show-config": ("Show sample config (dry run)",cmd_show_config),
    "deploy":      ("Deploy configuration",        cmd_deploy),
    "validate":    ("Validate configuration",      cmd_validate),
    "monitor":     ("Monitor network",             cmd_monitor),
    "all":         ("Run all steps",               cmd_all),
}


def print_help():
    print(f"\n{'='*60}")
    print("  CLOS NETWORK AUTOMATION SYSTEM")
    print(f"  Topology: {LAB_NAME} (21 devices, 3 tiers)")
    print(f"{'='*60}")
    print("\n  Usage: python main.py <command>\n")
    print(f"  {'Command':<14} {'Description'}")
    print(f"  {'-'*45}")
    for cmd, (desc, _) in COMMANDS.items():
        print(f"  {cmd:<14} {desc}")
    print()


if __name__ == "__main__":
    setup_logging()

    if len(sys.argv) < 2:
        print_help()
        sys.exit(0)

    command = sys.argv[1].lower()

    if command in ("help", "-h", "--help"):
        print_help()
    elif command in COMMANDS:
        _, func = COMMANDS[command]
        try:
            func()
        except FileNotFoundError as e:
            logging.error(f"Error: {e}")
            sys.exit(1)
        except KeyboardInterrupt:
            print("\n\nProcess interrupted by user.")
            sys.exit(130)
        except Exception as e:
            logging.exception(f"Unexpected error: {e}")
            sys.exit(1)
    else:
        print(f"\nInvalid command: '{command}'")
        print_help()
        sys.exit(1)