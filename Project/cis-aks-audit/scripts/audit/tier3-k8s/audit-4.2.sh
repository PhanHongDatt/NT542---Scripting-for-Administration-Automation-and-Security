#!/bin/bash
# =====================================================================
# audit-4.2.sh - CIS AKS Benchmark Controls 4.2.1 -> 4.2.5
# Kiểm tra các cấu hình bảo mật Pod (Sandbox Isolation)
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

report_init "4.2" "Pod Security"
log_section "ĐANG KIỂM TRA SECTION 4.2: POD SECURITY"

# Lấy TOÀN BỘ pods một lần (bỏ qua kube-system vì system pods cần quyền đặc biệt)
log_info "Đang tải dữ liệu tất cả Pods (ngoại trừ kube-system)..."
ALL_PODS=$(kubectl get pods -A -o json | jq '[.items[] | select(.metadata.namespace != "kube-system")]')
TOTAL_COUNT=$(echo "$ALL_PODS" | jq '. | length')
log_info "Tìm thấy $TOTAL_COUNT pods để kiểm tra."

# Hàm helper để kiểm tra các cờ host-level (Kỹ thuật DRY)
check_host_flag() {
    local id="$1"
    local field="$2"
    local desc="$3"
    
    log_info "Kiểm tra $id: $field..."
    local violating=$(echo "$ALL_PODS" | jq -r "[.[] | select(.spec.$field == true) | \"\(.metadata.namespace)/\(.metadata.name)\"] | unique | .[]" 2>/dev/null)
    
    if [ -z "$violating" ]; then
        report_add "$id" "PASS" "Không có Pod nào sử dụng $field=true."
    else
        local count=$(echo "$violating" | wc -l)
        report_add "$id" "FAIL" "$count Pod vi phạm $field: $(echo $violating | xargs)"
    fi
}

# 4.2.1 - Privileged containers
log_info "Kiểm tra 4.2.1: Privileged containers..."
PRIV_PODS=$(echo "$ALL_PODS" | jq -r '[.[] | select(.spec.containers[]?.securityContext?.privileged == true or .spec.initContainers[]?.securityContext?.privileged == true) | "\(.metadata.namespace)/\(.metadata.name)"] | unique | .[]' 2>/dev/null)
if [ -z "$PRIV_PODS" ]; then
    report_add "4.2.1" "PASS" "Không có container nào chạy quyền privileged."
else
    report_add "4.2.1" "FAIL" "Phát hiện Pod chạy privileged: $(echo $PRIV_PODS | xargs)"
fi

# 4.2.2, 4.2.3, 4.2.4 - Host Namespace Sharing
check_host_flag "4.2.2" "hostPID" "Hạn chế chia sẻ host PID namespace"
check_host_flag "4.2.3" "hostIPC" "Hạn chế chia sẻ host IPC namespace"
check_host_flag "4.2.4" "hostNetwork" "Hạn chế sử dụng host network"

# 4.2.5 - allowPrivilegeEscalation
log_info "Kiểm tra 4.2.5: allowPrivilegeEscalation..."
PRIVESC=$(echo "$ALL_PODS" | jq -r '[.[] | select(.spec.containers[]?.securityContext?.allowPrivilegeEscalation == true or .spec.initContainers[]?.securityContext?.allowPrivilegeEscalation == true) | "\(.metadata.namespace)/\(.metadata.name)"] | unique | .[]' 2>/dev/null)
if [ -z "$PRIVESC" ]; then
    report_add "4.2.5" "PASS" "Không có container nào cho phép leo thang đặc quyền."
else
    report_add "4.2.5" "FAIL" "Phát hiện Pod cho phép leo thang đặc quyền: $(echo $PRIVESC | xargs)"
fi

# In ra màn hình và lưu kết quả
report_print_summary
REPORT_DIR="$SCRIPT_DIR/../../../report"
report_save_json "$REPORT_DIR"
report_save_html "$REPORT_DIR"