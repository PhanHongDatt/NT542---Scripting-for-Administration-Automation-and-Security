#!/bin/bash
# =====================================================================
# audit-4.5+4.6.sh - CIS AKS Benchmark Controls 4.5.1 & 4.6.3
#
# Controls:
#   4.5.1 - Ưu tiên sử dụng Secret dưới dạng file (volume mount) thay vì env vars
#   4.6.3 - Không nên sử dụng namespace 'default' cho workloads
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

report_init "4.5+4.6" "Secrets and Namespaces"

# ─────────────────────────────────────────
#  CẤU HÌNH
# ─────────────────────────────────────────
SYSTEM_NS_REGEX="^(kube-system|kube-public|kube-node-lease|calico-system|tigera-operator|gatekeeper-system)$"

# ─────────────────────────────────────────
#  1. LẤY DỮ LIỆU PODS
# ─────────────────────────────────────────
log_info "Đang tải dữ liệu Pods cho Section 4.5 và 4.6..."
ALL_PODS_JSON=$(kubectl get pods -A -o json 2>/dev/null)

if [ -z "$ALL_PODS_JSON" ]; then
    log_fail "Không lấy được dữ liệu pods."
    exit 1
fi

# ─────────────────────────────────────────
#  4.5.1 - Prefer using secrets as files over env vars
#
#  Lý do: Biến môi trường dễ bị leak qua logs, inspect, hoặc tiến trình con.
#  Kiểm tra: Tìm các container sử dụng secretKeyRef hoặc secretRef trong env/envFrom.
# ─────────────────────────────────────────
check_4_5_1() {
    log_section "4.5.1 - Prefer using secrets as files over env vars"
    log_info "Lý do: Secret trong env var dễ bị lộ qua logs hoặc lệnh 'kubectl describe'"

    local violating_pods
    violating_pods=$(echo "$ALL_PODS_JSON" | jq -r --arg regex "$SYSTEM_NS_REGEX" '
        .items[] | select(.metadata.namespace | test($regex) | not) |
        . as $pod |
        .spec.containers[]? | 
        select(.env[]?.valueFrom?.secretKeyRef != null or .envFrom[]?.secretRef != null) |
        "\($pod.metadata.namespace)/\($pod.metadata.name) (container: \(.name))"
    ' 2>/dev/null)

    if [ -z "$violating_pods" ]; then
        log_pass "4.5.1: Không có Pod nào inject Secret qua biến môi trường ✓"
        report_add "4.5.1" "PASS" "Khong su dung Secret qua env vars"
    else
        local count
        count=$(echo "$violating_pods" | grep -c .)
        log_fail "4.5.1: Phát hiện $count container vi phạm! ✗"
        
        # In tối đa 5 cái
        echo "$violating_pods" | head -5 | while read -r line; do log_fail "  ↳ $line"; done
        
        report_add "4.5.1" "FAIL" "$count container dung Secret qua env vars"
    fi
}

# ─────────────────────────────────────────
#  4.6.3 - Ensure that the default namespace is not used
#
#  Lý do: Namespace 'default' không có các rào cản bảo mật mặc định.
#  Kiểm tra: Tìm các pods chạy trong ns 'default' (trừ các service hệ thống nếu có).
# ─────────────────────────────────────────
check_4_6_3() {
    log_section "4.6.3 - Ensure that the default namespace is not used"
    log_info "Lý do: Sử dụng namespace 'default' gây khó khăn trong việc áp dụng RBAC và Network Policy"

    local default_pods
    default_pods=$(echo "$ALL_PODS_JSON" | jq -r '
        .items[] | select(.metadata.namespace == "default") | 
        .metadata.name
    ' 2>/dev/null)

    if [ -z "$default_pods" ]; then
        log_pass "4.6.3: Namespace 'default' đang trống ✓"
        report_add "4.6.3" "PASS" "Namespace default khong co workloads"
    else
        local count
        count=$(echo "$default_pods" | grep -c .)
        log_fail "4.6.3: Phát hiện $count pod(s) đang chạy trong namespace 'default' ✗"
        
        # In tối đa 5 cái
        echo "$default_pods" | head -5 | while read -r line; do log_fail "  ↳ default/$line"; done
        
        report_add "4.6.3" "FAIL" "Phat hien $count pod trong namespace default"
    fi
}

# ── MAIN ─────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "${C_BLUE}  CIS AKS Benchmark v1.8.0 - Section 4.5 & 4.6        ${C_RESET}"
    echo -e "${C_BLUE}  Secrets and Namespaces                               ${C_RESET}"
    echo -e "${C_BLUE}========================================================${C_RESET}"

    check_4_5_1
    check_4_6_3

    report_print_summary
    local report_dir="$SCRIPT_DIR/../../../report"
    report_save_json "$report_dir"
    report_save_html "$report_dir"
}

main
