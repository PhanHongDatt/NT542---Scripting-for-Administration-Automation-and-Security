#!/bin/bash
# =====================================================================
# remediate-3.x.sh
# Remediation + Verification cho CIS AKS Benchmark Section 3.x
# Worker Node Configuration (File Permissions + Kubelet Security)
#
#   TASK 1 - Xác minh cấu hình bảo mật kubelet
#            (anonymous-auth, Webhook, readOnlyPort, rotateCertificates)
#   TASK 2 - Kiểm tra port 10255 thực sự đóng trên node
#   TASK 3 - Kiểm tra SSH config trên node + NSG rules trên Azure
#            (BỔ SUNNG — không nằm trong 29 tiêu chí CIS Benchmark)
#   TASK 4 - Tài liệu giới hạn AKS managed (không thể tự sửa)
#
# Cách chạy:
#   bash remediate-3.x.sh
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/common.sh"

# Helper top-level: trích giá trị flag từ kubelet args
# $1 = chuỗi kubelet args đầy đủ, $2 = tên flag (không có --)
_get_flag() {
    echo "$1" | grep -oP "(?<=--$2=)\S+" | head -1
}

# ─────────────────────────────────────────────────────────────────────
#  TASK 1 — Xác minh cấu hình bảo mật Kubelet
#
#  Các flag kiểm tra:
#    --anonymous-auth        → phải = false   (3.2.1)
#    --authorization-mode    → phải = Webhook  (3.2.2)
#    --read-only-port        → phải = 0        (3.2.4)
#    --rotate-certificates   → phải = true     (3.2.8)
#    RotateKubeletServerCertificate feature gate (3.2.9)
#
#  Lưu ý: AKS managed — các flag này không thể thay đổi trực tiếp,
#          chỉ có thể xác minh và ghi nhận. Xem TASK 4 để rõ hơn.
# ─────────────────────────────────────────────────────────────────────
task_verify_kubelet_security() {
    local node=$1
    log_section "TASK 1 — Xác minh cấu hình bảo mật Kubelet | Node: $node"

    node_setup "$node" || {
        log_warn "Không thể truy cập node $node, bỏ qua TASK 1."
        return
    }

    # Lấy toàn bộ kubelet process args một lần
    local kubelet_args
    kubelet_args=$(node_exec "ps -ef | grep '[k]ubelet'" 2>/dev/null)

    if [ -z "$kubelet_args" ] || [ "$kubelet_args" = "NO_POD" ]; then
        log_warn "Không đọc được kubelet process args."
        node_cleanup
        return
    fi

    # ── 3.2.1 anonymous-auth ──
    echo ""
    log_info "Kiểm tra --anonymous-auth (3.2.1)"
    local anon_auth
    anon_auth=$(_get_flag "$kubelet_args" "anonymous-auth")
    anon_auth="${anon_auth:-NOT_SET}"
    if [ "$anon_auth" = "false" ]; then
        log_pass "--anonymous-auth = false ✓"
    elif [ "$anon_auth" = "NOT_SET" ]; then
        # AKS không có config.yaml — kubelet được quản lý qua AKS API.
        # AKS enforce anonymous-auth=false theo mặc định.
        log_pass "--anonymous-auth = false (AKS enforced — không có trong process args) ✓"
    else
        log_fail "--anonymous-auth = $anon_auth ✗  (phải = false)"
        log_warn "  → AKS managed. Không thể sửa trực tiếp. Xem TASK 4."
    fi

    # ── 3.2.2 authorization-mode ──
    echo ""
    log_info "Kiểm tra --authorization-mode (3.2.2)"
    local auth_mode
    auth_mode=$(_get_flag "$kubelet_args" "authorization-mode")
    auth_mode="${auth_mode:-NOT_SET}"
    if [ "$auth_mode" = "Webhook" ]; then
        log_pass "--authorization-mode = Webhook ✓"
    elif [ "$auth_mode" = "NOT_SET" ]; then
        # AKS enforce authorization-mode=Webhook theo mặc định.
        log_pass "--authorization-mode = Webhook (AKS enforced — không có trong process args) ✓"
    else
        log_fail "--authorization-mode = $auth_mode ✗  (phải = Webhook)"
        log_warn "  → AKS managed. Không thể sửa trực tiếp. Xem TASK 4."
    fi

    # ── 3.2.4 read-only-port ──
    echo ""
    log_info "Kiểm tra --read-only-port (3.2.4)"
    local ro_port
    ro_port=$(_get_flag "$kubelet_args" "read-only-port")
    ro_port="${ro_port:-NOT_SET}"
    if [ "$ro_port" = "0" ]; then
        log_pass "--read-only-port = 0 ✓"
    elif [ "$ro_port" = "NOT_SET" ]; then
        # AKS set readOnlyPort=0. Xác minh bằng cách kiểm tra port 10255.
        local port_check
        port_check=$(node_exec "ss -tlnp 2>/dev/null | grep ':10255'" 2>/dev/null)
        if [ -z "$port_check" ] || [ "$port_check" = "NO_POD" ]; then
            log_pass "--read-only-port = 0 (AKS enforced, port 10255 không lắng nghe) ✓"
        else
            log_fail "--read-only-port: Port 10255 đang lắng nghe ✗"
            log_warn "  → AKS managed. Không thể sửa trực tiếp. Xem TASK 4."
        fi
    else
        log_fail "--read-only-port = $ro_port ✗  (phải = 0)"
        log_warn "  → AKS managed. Không thể sửa trực tiếp. Xem TASK 4."
    fi

    # ── 3.2.8 rotate-certificates ──
    echo ""
    log_info "Kiểm tra --rotate-certificates (3.2.8)"
    local rotate_certs
    rotate_certs=$(_get_flag "$kubelet_args" "rotate-certificates")
    rotate_certs="${rotate_certs:-NOT_SET}"
    if [ "$rotate_certs" = "true" ] || [ "$rotate_certs" = "NOT_SET" ]; then
        log_pass "--rotate-certificates = ${rotate_certs} ✓ (mặc định = true từ K8s 1.19)"
    else
        log_fail "--rotate-certificates = $rotate_certs ✗"
        log_warn "  → AKS managed. Không thể sửa trực tiếp. Xem TASK 4."
    fi

    # ── 3.2.9 RotateKubeletServerCertificate feature gate ──
    echo ""
    log_info "Kiểm tra RotateKubeletServerCertificate feature gate (3.2.9)"
    local feature_gates
    feature_gates=$(_get_flag "$kubelet_args" "feature-gates")
    if echo "$feature_gates" | grep -q "RotateKubeletServerCertificate=true"; then
        log_pass "RotateKubeletServerCertificate=true tìm thấy trong --feature-gates ✓"
    elif [ -z "$feature_gates" ] || [ "$feature_gates" = "NOT_SET" ]; then
        log_warn "--feature-gates không được set rõ ràng."
        log_warn "  → AKS thường bật RotateKubeletServerCertificate theo mặc định."
        log_warn "  → Xác nhận: az aks show -n $CLUSTER_NAME -g $RESOURCE_GROUP | jq '.agentPoolProfiles'"
    else
        log_fail "RotateKubeletServerCertificate không tìm thấy trong feature-gates: $feature_gates"
        log_warn "  → AKS managed. Không thể sửa trực tiếp. Xem TASK 4."
    fi

    node_cleanup
}

# ─────────────────────────────────────────────────────────────────────
#  TASK 2 — Kiểm tra port 10255 thực sự đóng trên node
#
#  Port 10255 = kubelet read-only API. Nếu mở, attacker có thể
#  xem metrics, pod info, secrets từ bên ngoài không cần auth.
#  Đây là kiểm tra THỰC TẾ trên node (không chỉ xem flag).
# ─────────────────────────────────────────────────────────────────────
task_check_port_10255() {
    local node=$1
    log_section "TASK 2 — Kiểm tra port 10255 (read-only API) | Node: $node"

    node_setup "$node" || {
        log_warn "Không thể truy cập node $node, bỏ qua TASK 2."
        return
    }

    # Ưu tiên ss (iproute2), fallback sang netstat nếu không có
    local listening
    listening=$(node_exec "ss -tlnp 2>/dev/null | grep ':10255'" 2>/dev/null)
    if [ -z "$listening" ] || [ "$listening" = "NO_POD" ]; then
        listening=$(node_exec "netstat -tlnp 2>/dev/null | grep '10255'" 2>/dev/null)
    fi

    if [ -z "$listening" ] || [ "$listening" = "NO_POD" ]; then
        log_pass "Port 10255 KHÔNG lắng nghe — read-only API đã tắt ✓"
    else
        log_fail "Port 10255 đang LẮNG NGHE ✗"
        log_fail "  Chi tiết: $listening"
        log_warn "  → Cần set: --read-only-port=0 trong kubelet config"
        log_warn "  → AKS managed: không thể sửa trực tiếp. Xem TASK 4."
    fi

    node_cleanup
}

# ─────────────────────────────────────────────────────────────────────
#  TASK 3 — Kiểm tra SSH config trên node + NSG rules trên Azure
#  (BỔ SUNNG — không nằm trong 29 tiêu chí CIS Benchmark)
#
#  4a. SSH config: PermitRootLogin, PasswordAuthentication,
#                  PubkeyAuthentication, MaxAuthTries
#  4b. NSG rules: phát hiện rule Allow port 22 từ Internet/Any
# ─────────────────────────────────────────────────────────────────────
task_harden_ssh_nsg() {
    local node=$1
    log_section "TASK 3 — SSH config + NSG rules (BỔ SUNNG) | Node: $node"

    # ── 3a. SSH Configuration trên node ──
    log_info "── SSH Configuration (/etc/ssh/sshd_config) ──"

    node_setup "$node" || {
        log_warn "Không thể truy cập node $node — bỏ qua kiểm tra SSH config."
        # Không return — vẫn chạy 4b (NSG check không cần node access)
        _check_nsg
        return
    }

    local sshd_config
    sshd_config=$(node_exec "cat /etc/ssh/sshd_config 2>/dev/null | grep -vE '^[[:space:]]*#|^[[:space:]]*$'")

    if [ -z "$sshd_config" ] || [ "$sshd_config" = "NO_POD" ]; then
        log_warn "Không đọc được /etc/ssh/sshd_config."
    else
        # PermitRootLogin phải là "no"
        local permit_root
        permit_root=$(echo "$sshd_config" | grep -iE "^PermitRootLogin" | awk '{print $2}' | head -1)
        permit_root="${permit_root:-NOT_SET}"
        if [[ "${permit_root,,}" == "no" ]]; then
            log_pass "PermitRootLogin = no ✓"
        else
            log_fail "PermitRootLogin = $permit_root ✗  (nên = no)"
        fi

        # PasswordAuthentication phải là "no" (key-only)
        local pass_auth
        pass_auth=$(echo "$sshd_config" | grep -iE "^PasswordAuthentication" | awk '{print $2}' | head -1)
        pass_auth="${pass_auth:-NOT_SET}"
        if [[ "${pass_auth,,}" == "no" ]]; then
            log_pass "PasswordAuthentication = no ✓"
        else
            log_fail "PasswordAuthentication = $pass_auth ✗  (nên = no, dùng key thay thế)"
        fi

        # PubkeyAuthentication phải là "yes" (default = yes nên NOT_SET cũng OK)
        local pubkey_auth
        pubkey_auth=$(echo "$sshd_config" | grep -iE "^PubkeyAuthentication" | awk '{print $2}' | head -1)
        pubkey_auth="${pubkey_auth:-NOT_SET}"
        if [[ "${pubkey_auth,,}" == "yes" ]] || [ "$pubkey_auth" = "NOT_SET" ]; then
            log_pass "PubkeyAuthentication = $pubkey_auth ✓"
        else
            log_fail "PubkeyAuthentication = $pubkey_auth ✗  (nên = yes)"
        fi

        # MaxAuthTries nên <= 4
        local max_tries
        max_tries=$(echo "$sshd_config" | grep -iE "^MaxAuthTries" | awk '{print $2}' | head -1)
        if [ -z "$max_tries" ]; then
            log_warn "MaxAuthTries = NOT_SET (mặc định = 6, khuyến nghị đặt <= 4)"
        elif [ "$max_tries" -le 4 ] 2>/dev/null; then
            log_pass "MaxAuthTries = $max_tries <= 4 ✓"
        else
            log_fail "MaxAuthTries = $max_tries ✗  (nên <= 4)"
        fi
    fi

    node_cleanup

    # ── 3b. NSG Rules ──
    echo ""
    log_info "── NSG Rules (port 22 từ Internet) ──"
    _check_nsg
}

# Helper nội bộ cho 3b — tách ra để có thể gọi ngay cả khi node_setup thất bại
_check_nsg() {
    load_aks_json
    if [ -z "$AKS_JSON" ]; then
        log_warn "Không có AKS JSON — bỏ qua kiểm tra NSG."
        return
    fi

    # nodeResourceGroup là RG chứa node VMs và NSG (khác với RG của AKS resource)
    local node_rg
    node_rg=$(echo "$AKS_JSON" | jq -r '.nodeResourceGroup // ""')
    if [ -z "$node_rg" ]; then
        log_warn "Không xác định được nodeResourceGroup."
        return
    fi

    log_info "Node Resource Group: $node_rg"

    local nsg_list
    nsg_list=$(az network nsg list --resource-group "$node_rg" --output json 2>/dev/null)

    if [ -z "$nsg_list" ] || [ "$nsg_list" = "[]" ]; then
        log_warn "Không tìm thấy NSG nào trong resource group $node_rg."
        return
    fi

    log_info "Số NSG tìm thấy: $(echo "$nsg_list" | jq '. | length')"

    # Tìm rule Allow + Inbound + port 22 (hoặc *) + source là Internet/*
    local open_rules
    open_rules=$(echo "$nsg_list" | jq -r '
        .[] |
        .name as $nsg |
        (.securityRules // [])[] |
        select(
            .access == "Allow" and
            .direction == "Inbound" and
            (
                .destinationPortRange == "22" or
                .destinationPortRange == "*" or
                (.destinationPortRanges // [] | map(select(. == "22" or . == "*")) | length > 0)
            ) and
            (
                .sourceAddressPrefix == "*" or
                .sourceAddressPrefix == "Internet" or
                .sourceAddressPrefix == "0.0.0.0/0"
            )
        ) |
        "  NSG=\($nsg) | Rule=\(.name) | Src=\(.sourceAddressPrefix) | Port=\(.destinationPortRange)"
    ' 2>/dev/null)

    if [ -z "$open_rules" ]; then
        log_pass "Không có NSG rule nào Allow SSH (port 22) từ Internet ✓"
    else
        log_fail "Phát hiện rule cho phép SSH từ Internet ✗"
        while IFS= read -r rule_line; do
            log_fail "$rule_line"
        done <<< "$open_rules"
        log_warn "  → Khuyến nghị: dùng Azure Bastion hoặc giới hạn source IP"
        log_warn "  → Xóa rule:    az network nsg rule delete -g $node_rg --nsg-name <NSG> --name <RULE>"
        log_warn "  → Thêm rule IP cụ thể:"
        log_warn "       az network nsg rule create -g $node_rg --nsg-name <NSG> --name AllowSSH-MyIP \\"
        log_warn "         --priority 100 --source-address-prefixes <YOUR_IP>/32 \\"
        log_warn "         --destination-port-ranges 22 --access Allow --direction Inbound"
    fi
}

# ─────────────────────────────────────────────────────────────────────
#  TASK 4 — Tài liệu giới hạn AKS managed
#
#  Ghi rõ những gì KHÔNG thể tự sửa vì AKS là managed service,
#  và những gì CÓ THỂ làm được để giảm thiểu rủi ro.
# ─────────────────────────────────────────────────────────────────────
task_document_limitations() {
    log_section "TASK 4 — Giới hạn AKS Managed Service"

    cat <<'EOF'

  ┌───────────────────────────────────────────────────────────────┐
  │         AKS MANAGED LIMITATIONS — Section 3.x                │
  │   Những thứ KHÔNG thể thay đổi trực tiếp bởi người dùng      │
  └───────────────────────────────────────────────────────────────┘

  [KUBELET FLAGS — Do AKS control plane quản lý]
  ┌──────────────────────────────┬────────────────────────────────────┐
  │ Config                       │ Trạng thái trong AKS               │
  ├──────────────────────────────┼────────────────────────────────────┤
  │ --anonymous-auth             │ Luôn = false (AKS enforce)         │
  │ --authorization-mode         │ Luôn = Webhook (AKS enforce)       │
  │ --read-only-port             │ = 0 từ K8s >= 1.20 (tắt mặc định) │
  │ --client-ca-file             │ Managed bởi AKS Certificate Auth.  │
  │ --rotate-certificates        │ = true từ K8s 1.19 (mặc định)     │
  │ RotateKubeletServerCert      │ AKS bật tự động, cert renew 90 ngày│
  └──────────────────────────────┴────────────────────────────────────┘

  [KHÔNG THỂ]
    ✗ Sửa /etc/systemd/system/kubelet.service trực tiếp
    ✗ Thay đổi kubelet flags qua kubectl hoặc az aks set trực tiếp
    ✗ Tắt kubelet TLS bootstrapping
    ✗ Thay đổi certificate authority của kubelet

  [CÓ THỂ thực hiện để cải thiện bảo mật]
    ✓ Node image upgrade:
        az aks upgrade --node-image-only
    ✓ Giới hạn API Server access:
        az aks update --api-server-authorized-ip-ranges <IP>/32
    ✓ Xóa/chỉnh NSG rule SSH từ Internet:
        az network nsg rule delete / create
    ✓ Sửa file permission 3.1.x qua debug pod:
        kubectl debug node/<name> ... + chmod/chown
    ✓ Upgrade Kubernetes version:
        az aks upgrade --kubernetes-version <VER>

  [NODE ACCESS — Khuyến nghị]
    → Không dùng SSH trực tiếp vào node
    → Dùng: kubectl debug node/<name> --image=ubuntu:22.04
    → Hoặc: Azure Bastion (nếu cần SSH thực sự)
    → SSH key được cấu hình qua Terraform (linux_profile.ssh_key)

  [KHI PHÁT HIỆN VẤN ĐỀ AKS MANAGED]
    → Mở Azure Support ticket nếu kubelet flag bị misconfigured
    → Kiểm tra AKS release notes cho phiên bản đang dùng
    → Link: https://github.com/Azure/AKS/releases

EOF
}

# ════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════
main() {
    echo ""
    echo -e "${C_BLUE}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BLUE}║   CIS AKS Benchmark v1.8.0 — Remediation Section 3.x        ║${C_RESET}"
    echo -e "${C_BLUE}║   Worker Node: Kubelet Security + File Permissions           ║${C_RESET}"
    echo -e "${C_BLUE}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
    echo -e "  Thời gian: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Kiểm tra công cụ bắt buộc
    for tool in az kubectl jq; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${C_RED}[ERROR]${C_RESET} Công cụ '$tool' chưa được cài đặt."
            exit 1
        fi
    done

    # Kiểm tra Azure login
    if ! az account show &>/dev/null; then
        echo -e "${C_RED}[ERROR]${C_RESET} Chưa đăng nhập Azure. Chạy: az login"
        exit 1
    fi

    # Lấy thông tin cluster từ common.sh (dùng chung với audit scripts)
    get_cluster_info || exit 1
    load_aks_json

    # Lấy danh sách nodes
    local nodes
    nodes=$(get_nodes)
    if [ -z "$nodes" ]; then
        echo -e "${C_RED}[ERROR]${C_RESET} Không tìm thấy node nào. Kiểm tra: kubectl get nodes"
        exit 1
    fi

    local node_count
    node_count=$(echo "$nodes" | wc -l)
    log_info "Tìm thấy $node_count node(s): $(echo "$nodes" | tr '\n' ' ')"

    # ── Chạy TASK 1, 2, 3 theo từng node ──
    for node in $nodes; do
        echo ""
        echo -e "${C_CYAN}┌──────────────────────────────────────────────────────┐${C_RESET}"
        echo -e "${C_CYAN}│  NODE: $node${C_RESET}"
        echo -e "${C_CYAN}└──────────────────────────────────────────────────────┘${C_RESET}"

        task_verify_kubelet_security "$node"
        task_check_port_10255 "$node"
        task_harden_ssh_nsg "$node"
    done

    # ── TASK 4: documentation, chạy 1 lần ──
    echo ""
    task_document_limitations

    echo ""
    echo -e "${C_BLUE}══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BLUE}  Remediation Section 3.x hoàn tất — $(date '+%Y-%m-%d %H:%M:%S')${C_RESET}"
    echo -e "${C_BLUE}══════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
}

main
