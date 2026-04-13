#!/bin/bash
# =====================================================================
# audit-4.1.sh - CIS AKS Benchmark Controls 4.1.1 & 4.1.3
# Tập trung vào rà soát quyền Cluster-admin và Wildcard Roles
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

# Khởi tạo báo cáo cho Section 4.1
report_init "4.1" "RBAC and Service Accounts"
log_section "ĐANG KIỂM TRA SECTION 4.1: RBAC"

# ---------------------------------------------------------------------
# 4.1.1 - cluster-admin role chỉ dùng khi thực sự cần
# ---------------------------------------------------------------------
log_info "Kiểm tra 4.1.1: cluster-admin role bindings..."

# Lọc các bindings KHÔNG phải hệ thống (không bắt đầu bằng system: hoặc aks-)
NON_SYSTEM=$(kubectl get clusterrolebindings -o json | jq -r \
  '[.items[] | select(.roleRef.name=="cluster-admin") | 
  select(.subjects != null) |
  select(.subjects[]? | 
    (.name | startswith("system:") | not) and 
    (.name | startswith("aks-") | not)
  ) | .metadata.name] | unique | .[]' 2>/dev/null)

if [ -z "$NON_SYSTEM" ]; then
    report_add "4.1.1" "PASS" "Chỉ các tài khoản hệ thống mới có quyền cluster-admin."
else
    count=$(echo "$NON_SYSTEM" | wc -l)
    report_add "4.1.1" "FAIL" "Phát hiện $count binding không thuộc hệ thống có quyền God-mode: $(echo $NON_SYSTEM | xargs)"
fi

# ---------------------------------------------------------------------
# 4.1.3 - Hạn chế sử dụng Wildcard (*) trong Roles/ClusterRoles
# ---------------------------------------------------------------------
log_info "Kiểm tra 4.1.3: Sử dụng wildcard (*) trong Roles..."

# Quét ClusterRoles (bỏ qua system roles)
WILD_CROLES=$(kubectl get clusterroles -o json | jq -r \
  '[.items[] | select(.metadata.name | startswith("system:") | not) | 
  select(.metadata.name | startswith("aks:") | not) |
  select(.rules[]? | (.resources? // [] | index("*")) or (.verbs? // [] | index("*"))) 
  | .metadata.name] | unique | .[]' 2>/dev/null)

# Quét Roles trong mọi namespace
WILD_ROLES=$(kubectl get roles -A -o json | jq -r \
  '[.items[] | select(.rules[]? | (.resources? // [] | index("*")) or (.verbs? // [] | index("*"))) 
  | "\(.metadata.namespace)/\(.metadata.name)"] | unique | .[]' 2>/dev/null)

TOTAL_WILD=$(( $(echo "$WILD_CROLES" | grep -c .) + $(echo "$WILD_ROLES" | grep -c .) ))

if [ "$TOTAL_WILD" -eq 0 ]; then
    report_add "4.1.3" "PASS" "Không phát hiện wildcard (*) trong các Roles tùy chỉnh."
else
    report_add "4.1.3" "FAIL" "Phát hiện $TOTAL_WILD Roles sử dụng wildcard (*), vi phạm nguyên tắc đặc quyền tối thiểu."
fi

# In ra màn hình và lưu kết quả
report_print_summary
REPORT_DIR="$SCRIPT_DIR/../../../report"
report_save_json "$REPORT_DIR"
report_save_html "$REPORT_DIR"