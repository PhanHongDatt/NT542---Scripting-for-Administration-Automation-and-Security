#!/bin/bash
# ============================================================
#  audit-3.2.sh - CIS AKS Benchmark v1.8.0 - Section 3.2
#  Worker Node Configuration - Kubelet
#
#  Controls:
#    3.2.1 - anonymous-auth = false
#    3.2.2 - authorization-mode != AlwaysAllow
#    3.2.3 - client-ca-file được set và tồn tại
#    3.2.4 - read-only-port = 0
#    3.2.5 - streaming-connection-idle-timeout != 0
#    3.2.6 - make-iptables-util-chains = true
#    3.2.7 - event-qps >= 0 [Level 2]
#    3.2.8 - rotate-certificates != false [Level 2]
#    3.2.9 - RotateKubeletServerCertificate = true
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

report_init "3.2" "Worker Node Kubelet Configuration"

# ─────────────────────────────────────────
#  Biến lưu kubelet args (lấy 1 lần, dùng cho tất cả checks)
# ─────────────────────────────────────────
KUBELET_ARGS=""

load_kubelet_args() {
    # AKS không dùng config file YAML mà truyền tất cả qua process args
    # Ví dụ: /opt/bin/kubelet --anonymous-auth=false --read-only-port=0 ...
    KUBELET_ARGS=$(node_exec \
        "ps -ef | grep -E '/opt/bin/kubelet|/usr/bin/kubelet' | grep -v grep | head -1")

    if [ -z "$KUBELET_ARGS" ] || [ "$KUBELET_ARGS" = "ERROR" ] || [ "$KUBELET_ARGS" = "NO_POD" ]; then
        log_warn "Không lấy được kubelet args!"
        KUBELET_ARGS=""
        return 1
    fi
    log_info "Đã lấy kubelet process args."
    return 0
}

# ─────────────────────────────────────────
#  HÀM: Lấy giá trị 1 flag từ kubelet args
#  Dùng grep -oP (Perl regex) để tránh lỗi dấu "--"
#
#  Ví dụ:
#    get_arg "--read-only-port"  → "0"
#    get_arg "--anonymous-auth"  → "false"
#    get_arg "--khong-co"        → "NOT_SET"
# ─────────────────────────────────────────
get_arg() {
    local flag=$1
    local default="${2:-NOT_SET}"
    local value
    value=$(echo "$KUBELET_ARGS" | grep -oP "(?<=[ ])${flag}=\S+" \
        | cut -d= -f2- | head -1)
    [ -z "$value" ] && echo "$default" || echo "$value"
}

# ── 3.2.1 ─────────────────────────────────────────────────────
check_3_2_1() {
    log_section "3.2.1 - Ensure --anonymous-auth = false"
    log_info "Lý do: anonymous-auth=true cho phép bất kỳ ai gọi Kubelet API không cần xác thực"

    local value
    value=$(get_arg "--anonymous-auth")
    log_info "--anonymous-auth = $value"

    if [ "$value" = "false" ]; then
        log_pass "3.2.1: --anonymous-auth = false ✓"
        report_add "3.2.1" "PASS" "--anonymous-auth = false"
    elif [ "$value" = "NOT_SET" ]; then
        # Kubernetes default = true nếu không set → FAIL
        log_fail "3.2.1: --anonymous-auth không set → mặc định true ✗"
        report_add "3.2.1" "FAIL" "--anonymous-auth khong set (mac dinh true)"
    else
        log_fail "3.2.1: --anonymous-auth = $value ✗"
        report_add "3.2.1" "FAIL" "--anonymous-auth = $value"
    fi
}

# ── 3.2.2 ─────────────────────────────────────────────────────
check_3_2_2() {
    log_section "3.2.2 - Ensure --authorization-mode != AlwaysAllow"
    log_info "Lý do: AlwaysAllow bỏ qua toàn bộ RBAC → mọi request đều được chấp nhận"

    local value
    value=$(get_arg "--authorization-mode")
    log_info "--authorization-mode = $value"

    if [ "$value" = "AlwaysAllow" ]; then
        log_fail "3.2.2: --authorization-mode = AlwaysAllow ✗ (rất nguy hiểm!)"
        report_add "3.2.2" "FAIL" "--authorization-mode = AlwaysAllow"
    elif [ "$value" = "NOT_SET" ]; then
        log_warn "3.2.2: --authorization-mode không set → cần kiểm tra thủ công"
        report_add "3.2.2" "WARN" "--authorization-mode khong set"
    else
        log_pass "3.2.2: --authorization-mode = $value ✓"
        report_add "3.2.2" "PASS" "--authorization-mode = $value"
    fi
}

# ── 3.2.3 ─────────────────────────────────────────────────────
check_3_2_3() {
    log_section "3.2.3 - Ensure --client-ca-file được set"
    log_info "Lý do: CA file cho phép kubelet xác minh certificate của API server"

    local value
    value=$(get_arg "--client-ca-file")
    log_info "--client-ca-file = $value"

    if [ "$value" = "NOT_SET" ]; then
        log_fail "3.2.3: --client-ca-file chưa được set ✗"
        report_add "3.2.3" "FAIL" "--client-ca-file = NOT_SET"
    else
        # Kiểm tra file có thực sự tồn tại trên node
        local exists
        exists=$(node_exec "[ -f '$value' ] && echo yes || echo no")
        if [ "$exists" = "yes" ]; then
            log_pass "3.2.3: --client-ca-file = $value (file tồn tại) ✓"
            report_add "3.2.3" "PASS" "--client-ca-file = $value"
        else
            log_fail "3.2.3: --client-ca-file = $value nhưng FILE KHÔNG TỒN TẠI ✗"
            report_add "3.2.3" "FAIL" "File khong ton tai: $value"
        fi
    fi
}

# ── 3.2.4 ─────────────────────────────────────────────────────
check_3_2_4() {
    log_section "3.2.4 - Ensure --read-only-port = 0"
    log_info "Lý do: Port 10255 expose thông tin pods/nodes mà không cần xác thực"

    local value
    value=$(get_arg "--read-only-port")
    log_info "--read-only-port = $value"

    if [ "$value" = "0" ]; then
        log_pass "3.2.4: --read-only-port = 0 (disabled) ✓"
        report_add "3.2.4" "PASS" "--read-only-port = 0"
    elif [ "$value" = "NOT_SET" ]; then
        log_warn "3.2.4: --read-only-port không set → có thể mặc định 10255"
        report_add "3.2.4" "WARN" "--read-only-port khong set"
    else
        log_fail "3.2.4: --read-only-port = $value ✗ (cần = 0)"
        report_add "3.2.4" "FAIL" "--read-only-port = $value"
    fi
}

# ── 3.2.5 ─────────────────────────────────────────────────────
check_3_2_5() {
    log_section "3.2.5 - Ensure --streaming-connection-idle-timeout != 0"
    log_info "Lý do: Timeout=0 giữ connections mở vĩnh viễn → nguy cơ session hijacking"

    local value
    value=$(get_arg "--streaming-connection-idle-timeout")
    log_info "--streaming-connection-idle-timeout = $value"

    if [ "$value" = "0" ] || [ "$value" = "0s" ]; then
        log_fail "3.2.5: --streaming-connection-idle-timeout = 0 ✗"
        report_add "3.2.5" "FAIL" "--streaming-connection-idle-timeout = 0"
    elif [ "$value" = "NOT_SET" ]; then
        # Kubernetes default = 4h → OK
        log_pass "3.2.5: Không set → mặc định 4h (khác 0) ✓"
        report_add "3.2.5" "PASS" "--streaming-connection-idle-timeout = 4h (mac dinh)"
    else
        log_pass "3.2.5: --streaming-connection-idle-timeout = $value ✓"
        report_add "3.2.5" "PASS" "--streaming-connection-idle-timeout = $value"
    fi
}

# ── 3.2.6 ─────────────────────────────────────────────────────
check_3_2_6() {
    log_section "3.2.6 - Ensure --make-iptables-util-chains = true"
    log_info "Lý do: Kubelet cần quản lý iptables để đảm bảo network routing đúng"

    local value
    value=$(get_arg "--make-iptables-util-chains")
    log_info "--make-iptables-util-chains = $value"

    if [ "$value" = "false" ]; then
        log_fail "3.2.6: --make-iptables-util-chains = false ✗"
        report_add "3.2.6" "FAIL" "--make-iptables-util-chains = false"
    else
        local display="${value/NOT_SET/true (mac dinh)}"
        log_pass "3.2.6: --make-iptables-util-chains = $display ✓"
        report_add "3.2.6" "PASS" "--make-iptables-util-chains = $display"
    fi
}

# ── 3.2.7 ─────────────────────────────────────────────────────
check_3_2_7() {
    log_section "3.2.7 - Ensure --event-qps >= 0 [Level 2]"
    log_info "Lý do: Rate quá thấp có thể bỏ sót security events quan trọng"

    local value
    value=$(get_arg "--event-qps")
    log_info "--event-qps = $value"

    if [ "$value" = "NOT_SET" ]; then
        log_pass "3.2.7: Không set → mặc định 50 (>= 0) ✓"
        report_add "3.2.7" "PASS" "--event-qps = 50 (mac dinh)"
    elif [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 0 ]; then
        log_pass "3.2.7: --event-qps = $value (>= 0) ✓"
        report_add "3.2.7" "PASS" "--event-qps = $value"
    else
        log_fail "3.2.7: --event-qps = $value ✗"
        report_add "3.2.7" "FAIL" "--event-qps = $value"
    fi
}

# ── 3.2.8 ─────────────────────────────────────────────────────
check_3_2_8() {
    log_section "3.2.8 - Ensure --rotate-certificates != false [Level 2]"
    log_info "Lý do: Certificate rotation đảm bảo kubelet luôn có cert hợp lệ"

    local value
    value=$(get_arg "--rotate-certificates")
    log_info "--rotate-certificates = $value"

    if [ "$value" = "false" ]; then
        log_fail "3.2.8: --rotate-certificates = false ✗"
        report_add "3.2.8" "FAIL" "--rotate-certificates = false"
    else
        local display="${value/NOT_SET/true (mac dinh)}"
        log_pass "3.2.8: --rotate-certificates = $display ✓"
        report_add "3.2.8" "PASS" "--rotate-certificates = $display"
    fi
}

# ── 3.2.9 ─────────────────────────────────────────────────────
check_3_2_9() {
    log_section "3.2.9 - Ensure RotateKubeletServerCertificate = true"
    log_info "Lý do: Server cert rotation tự động thay cert hết hạn, tránh gián đoạn"

    # Nằm trong --feature-gates=RotateKubeletServerCertificate=true,...
    local feature_gates
    feature_gates=$(get_arg "--feature-gates")
    log_info "--feature-gates = $feature_gates"

    local value="NOT_SET"
    if [ "$feature_gates" != "NOT_SET" ]; then
        value=$(echo "$feature_gates" | \
            grep -oP 'RotateKubeletServerCertificate=\w+' | cut -d= -f2)
        [ -z "$value" ] && value="NOT_SET"
    fi

    log_info "RotateKubeletServerCertificate = $value"

    if [ "$value" = "true" ]; then
        log_pass "3.2.9: RotateKubeletServerCertificate = true ✓"
        report_add "3.2.9" "PASS" "RotateKubeletServerCertificate = true (feature-gates)"
    elif [ "$value" = "false" ]; then
        log_fail "3.2.9: RotateKubeletServerCertificate = false ✗"
        report_add "3.2.9" "FAIL" "RotateKubeletServerCertificate = false"
    else
        # K8s >= 1.12 mặc định true
        log_pass "3.2.9: Không set → mặc định true (K8s >= 1.12) ✓"
        report_add "3.2.9" "PASS" "RotateKubeletServerCertificate = true (mac dinh)"
    fi
}

# ── MAIN ─────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "${C_BLUE}  CIS AKS Benchmark v1.8.0 - Section 3.2              ${C_RESET}"
    echo -e "${C_BLUE}  Worker Node Configuration - Kubelet                  ${C_RESET}"
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "  Thời gian: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local nodes
    nodes=$(get_nodes)
    if [ -z "$nodes" ]; then
        echo -e "${C_RED}[ERROR]${C_RESET} Không tìm thấy node! Kiểm tra: kubectl get nodes"
        exit 1
    fi

    log_info "Tìm thấy $(echo "$nodes" | wc -l) node(s)"

    for node in $nodes; do
        echo ""
        echo -e "${C_BLUE}╔══════════════════════════════════════════╗${C_RESET}"
        echo -e "${C_BLUE}║  NODE: $node${C_RESET}"
        echo -e "${C_BLUE}╚══════════════════════════════════════════╝${C_RESET}"

        node_setup "$node" || { log_warn "Bỏ qua node $node."; continue; }

        # Lấy kubelet args 1 lần cho tất cả checks
        load_kubelet_args || { node_cleanup; continue; }

        check_3_2_1
        check_3_2_2
        check_3_2_3
        check_3_2_4
        check_3_2_5
        check_3_2_6
        check_3_2_7
        check_3_2_8
        check_3_2_9

        node_cleanup
    done

    report_print_summary
    local report_dir="$SCRIPT_DIR/../../../report"
    report_save_json "$report_dir"
    report_save_html "$report_dir"
}

main