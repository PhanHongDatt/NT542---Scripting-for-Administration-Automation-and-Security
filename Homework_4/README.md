# MongoDB Replica Set — Hướng dẫn Triển khai (HW4)

## Kiến trúc hệ thống

| Role | Hostname | Instance Type | Private IP | Public IP |
|---|---|---|---|---|
| Ansible Control | ansible-control | t3.micro | 172.31.65.146 | 3.235.146.140 |
| MongoDB Primary | mongo-01 | t3.small | 172.31.66.74 | 98.93.1.182 |
| MongoDB Secondary | mongo-02 | t3.small | 172.31.68.157 | 3.238.196.208 |
| MongoDB Secondary | mongo-03 | t3.small | 172.31.67.144 | 44.210.236.129 |
| MongoDB Secondary | mongo-04 | t3.small | 172.31.67.224 | 44.200.194.217 |
| MongoDB Secondary | mongo-05 | t3.small | 172.31.67.134 | 44.221.75.89 |

## Cấu trúc thư mục

```
mongodb-automation-hw4/
├── ansible.cfg
├── DEPLOYMENT.md
├── inventory/
│   ├── hosts.ini                          # Danh sách hosts + Private IP
│   └── group_vars/
│       └── mongodb.yml                    # Biến dùng chung cho tất cả nodes
├── playbooks/
│   ├── deploy_mongodb.yml                 # Yêu cầu 1: Deploy full cluster
│   ├── upgrade_mongodb.yml                # Yêu cầu 2: Zero-downtime upgrade
│   ├── fix_hosts.yml                      # Utility: Cấu hình /etc/hosts
│   └── fix_pymongo.yml                    # Utility: Nâng cấp pymongo >= 4.0
├── roles/
│   ├── mongodb_install/                   # Role: Cài đặt & cấu hình MongoDB
│   │   ├── defaults/main.yml              #   Biến mặc định của role
│   │   ├── handlers/main.yml              #   Handlers: enable-thp, restart mongod
│   │   ├── tasks/main.yml                 #   Tasks: install + configure
│   │   └── templates/mongod.conf.j2       #   Template cấu hình mongod
│   ├── mongodb_replicaset/                # Role: Khởi tạo & verify Replica Set
│   │   └── tasks/main.yml                 #   Tasks: rs.initiate + verify
│   └── mongodb_upgrade/                   # Role: Rolling upgrade từng node
│       └── tasks/main.yml                 #   Tasks: stop → upgrade → rejoin
└── templates/
    └── mongod.conf.j2                     # Template dùng trực tiếp từ playbook
```

---

## Bước 0 — Chuẩn bị Ansible Control Node

```bash
# Cập nhật hệ thống
sudo apt update && sudo apt upgrade -y

# Cài Ansible >= 2.14
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible python3-pip

# Kiểm tra version
ansible --version   # cần >= 2.14
python3 --version   # cần >= 3.9

# Cài MongoDB collection (bắt buộc)
ansible-galaxy collection install community.mongodb
```

---

## Bước 1 — Cấu hình SSH Key

```bash
# Tạo key để Ansible kết nối tới các MongoDB node
ssh-keygen -t ed25519 -f ~/.ssh/mongodb_key -N ""

# Copy public key sang từng node (dùng key .pem gốc của AWS lần đầu)
for IP in 98.93.1.182 3.238.196.208 44.210.236.129 44.200.194.217 44.221.75.89; do
  ssh-copy-id -i ~/.ssh/mongodb_key.pub \
    -o StrictHostKeyChecking=no \
    -o IdentityFile=~/NT542-lab.pem \
    ubuntu@$IP
done
```

---

## Bước 2 — Cấu hình /etc/hosts trên tất cả 6 nodes

Chạy trên **mỗi node** (bao gồm cả ansible-control):

```bash
sudo tee -a /etc/hosts <<EOF
# MongoDB Cluster - Private IPs
172.31.66.74   mongo-01
172.31.68.157  mongo-02
172.31.67.144  mongo-03
172.31.67.224  mongo-04
172.31.67.134  mongo-05
EOF
```

Hoặc dùng playbook Ansible (chỉ cho 5 MongoDB nodes):

```bash
cd ~/mongodb-automation-hw4
ansible-playbook playbooks/fix_hosts.yml
```

---

## Bước 3 — Kiểm tra kết nối

```bash
cd ~/mongodb-automation-hw4

# Ping tất cả 5 nodes
ansible mongodb -m ping

# Kiểm tra quyền sudo và Python
ansible mongodb -m shell -a "python3 --version && sudo whoami"
```

Kết quả mong đợi: tất cả 5 nodes trả về `"ping": "pong"`.

---

## Bước 4 — Nâng cấp pymongo lên 4.0+

> Bắt buộc trên Ubuntu 22.04 vì `python3-pymongo` mặc định < 4.0

```bash
ansible-playbook playbooks/fix_pymongo.yml
```

---

## Bước 5 — Deploy MongoDB (Yêu cầu 1)

```bash
ansible-playbook playbooks/deploy_mongodb.yml
```

Playbook thực hiện **5 phases**:
- Phase 1: Update apt cache + cài prerequisite packages
- Phase 2: Disable THP + cấu hình system limits
- Phase 3: Cài MongoDB 7.0 + deploy `mongod.conf` + start service
- Phase 4: Khởi tạo Replica Set `rs0` trên `mongo-01`
- Phase 5: Verify tất cả 5 members healthy

### Kiểm tra sau deploy

```bash
# Kiểm tra version MongoDB trên tất cả nodes
ansible mongodb -m shell -a "mongod --version && cat /etc/mongod.conf" --become

# Kiểm tra Replica Set status
ssh -i ~/.ssh/mongodb_key ubuntu@172.31.66.74 \
  "mongosh --quiet --eval '
    var s = rs.status();
    print(\"Replica Set:\", s.set);
    s.members.forEach(m => print(\" -\", m.name, \"|\", m.stateStr));
  '"

# Kiểm tra sức khoẻ cluster
ssh -i ~/.ssh/mongodb_key ubuntu@172.31.66.74 \
  "mongosh --quiet --eval '
    var s = rs.status();
    print(\"=== CLUSTER HEALTH ===\");
    print(\"State:\", s.ok == 1 ? \"HEALTHY\" : \"UNHEALTHY\");
    print(\"Total members:\", s.members.length);
    var primary = s.members.filter(m => m.stateStr == \"PRIMARY\");
    var secondary = s.members.filter(m => m.stateStr == \"SECONDARY\");
    print(\"Primary:\", primary.length);
    print(\"Secondary:\", secondary.length);
  '"
```

---

## Bước 6 — Zero-Downtime Upgrade (Yêu cầu 2)

```bash
# Dry-run trước để kiểm tra
ansible-playbook playbooks/upgrade_mongodb.yml --check

# Chạy thực tế
ansible-playbook playbooks/upgrade_mongodb.yml
```

### Cơ chế rolling upgrade

```
mongo-02 → mongo-03 → mongo-04 → mongo-05  (serial: 1, từng node một)
    ↓ Mỗi node: stop → upgrade → start → confirm SECONDARY ✅
mongo-01 (Primary):
    rs.stepDown(60)  →  election (~15s)  →  stop → upgrade → start → rejoin
```

> Kết quả: `mongo-01` lấy lại PRIMARY (priority = 10), 4 secondary ổn định.

### Kiểm tra sau upgrade

```bash
# Kiểm tra version trên tất cả nodes
ansible mongodb -m shell -a "mongod --version" --become

# Kiểm tra trạng thái cluster
ssh -i ~/.ssh/mongodb_key ubuntu@172.31.66.74 \
  "mongosh --quiet --eval '
    var s = rs.status();
    print(\"=== POST-UPGRADE CLUSTER STATUS ===\");
    s.members.forEach(m => print(\" -\", m.name, \"|\", m.stateStr));
  '"
```

---

## Bước 7 — Application Connectivity (Yêu cầu 3)

Dùng **Replica Set connection string** thay vì kết nối single node:

```
mongodb://mongo-01:27017,mongo-02:27017,mongo-03:27017,mongo-04:27017,mongo-05:27017/?replicaSet=rs0
```

### 3 cơ chế tự động của MongoDB Driver

| Cơ chế | Mô tả |
|---|---|
| **SDAM** | Driver ping tất cả members mỗi vài giây, tự detect node unavailable |
| **Read/Write Routing** | Write → PRIMARY, Read → có thể phân tán ra SECONDARY |
| **Auto Failover** | Khi PRIMARY step down, driver tự detect Primary mới và redirect write |

> Application chỉ bị gián đoạn tối đa ~15 giây trong election window.

---

## Tham chiếu nhanh

| Lệnh | Mục đích |
|---|---|
| `ansible mongodb -m ping` | Kiểm tra kết nối tất cả nodes |
| `ansible-playbook playbooks/fix_hosts.yml` | Cấu hình /etc/hosts |
| `ansible-playbook playbooks/fix_pymongo.yml` | Nâng cấp pymongo |
| `ansible-playbook playbooks/deploy_mongodb.yml` | Deploy cluster lần đầu |
| `ansible-playbook playbooks/upgrade_mongodb.yml --check` | Dry-run upgrade |
| `ansible-playbook playbooks/upgrade_mongodb.yml` | Rolling upgrade |
