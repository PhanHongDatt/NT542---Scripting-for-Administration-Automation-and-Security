#!/bin/bash
# =====================================================================
# audit-4.2.sh - CIS AKS Benchmark v1.8.0 - Section 4.2
# Pod Security Standards
# ---------------------------------------------------------------------
# Controls:
#   4.2.1 - Minimize admission of privileged containers
#   4.2.2 - Minimize containers sharing host PID namespace
#   4.2.3 - Minimize containers sharing host IPC namespace
#   4.2.4 - Minimize containers sharing host network namespace
#   4.2.5 - Minimize containers with allowPrivilegeEscalation
# =====================================================================

# Lấy đường dẫn tuyệt đối của thư mục chứa script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

# ─────────────────────────────────────────
#  HEADER & THÔNG TIN CHUNG
# ─────────────────────────────────────────
echo -e "\n${C_BLUE}========================================================${C_RESET}"
echo -e "${C_BLUE}   CIS AKS Benchmark v1.8.0 - Section 4.2${C_RESET}"
echo -e "${C_BLUE}   Pod Security Standards${C_RESET}"
echo -e "${C_BLUE}========================================================${C_RESET}"
echo -e "   Thời gian: $(date '+%Y-%m-%d %H:%M:%S')\n"

# Khởi tạo báo cáo
report_init "4.2" "Pod Security Standards"

# ─────────────────────────────────────────
#  CẤU HÌNH
# ─────────────────────────────────────────
# Danh sách namespace hệ thống → bỏ qua khi audit (AKS quản lý, không sửa được)
SYSTEM_NS_REGEX="^(kube-system|kube-public|kube-node-lease|calico-system|tigera-operator|gatekeeper-system)$"

# ─────────────────────────────────────────
#  1. LẤY DỮ LIỆU PODS (chỉ 1 lần duy nhất)
# ─────────────────────────────────────────
log_info "Đang lấy danh sách tất cả Pods trong cluster..."

ALL_PODS_JSON=$(kubectl get pods -A -o json 2>/dev/null)

if [ -z "$ALL_PODS_JSON" ] || [ "$(echo "$ALL_PODS_JSON" | jq '.items | length')" -eq 0 ]; then
    log_warn "Không tìm thấy pod nào đang chạy trong cluster."
    log_warn "Hãy kiểm tra: kubectl get pods -A"
    exit 1
fi

TOTAL_PODS=$(echo "$ALL_PODS_JSON" | jq '.items | length')
log_info "Tìm thấy tổng cộng ${C_CYAN}$TOTAL_PODS${C_RESET} pod(s) trong cluster."

# Đếm pods user vs system
USER_PODS=$(echo "$ALL_PODS_JSON" | jq --arg regex "$SYSTEM_NS_REGEX" \
    '[.items[] | select(.metadata.namespace | test($regex) | not)] | length')
SYSTEM_PODS=$((TOTAL_PODS - USER_PODS))
log_info "Phân loại: ${C_CYAN}$USER_PODS${C_RESET} user pods | ${C_YELLOW}$SYSTEM_PODS${C_RESET} system pods (bỏ qua)"

# ─────────────────────────────────────────
#  HÀM KIỂM TRA CHUNG CHO POD SECURITY
# ─────────────────────────────────────────
# Tham số:
#   $1: Control ID (vd: 4.2.1)
#   $2: Tên control (vd: "privileged containers")
#   $3: jq filter trả về danh sách pods vi phạm (mỗi dòng = "namespace/pod-name")
#   $4: Giải thích lý do kiểm tra
check_pod_security() {
    local control_id=$1
    local control_name=$2
    local jq_filter=$3
    local reason=$4

    log_section "$control_id - $control_name"
    log_info "Lý do: $reason"

    # Chạy jq filter để tìm pods vi phạm (chỉ user namespaces)
    local violators
    violators=$(echo "$ALL_PODS_JSON" | jq -r --arg regex "$SYSTEM_NS_REGEX" "$jq_filter" 2>/dev/null)

    # Đếm số dòng kết quả (loại bỏ dòng trống)
    local count=0
    local pod_list=""
    if [ -n "$violators" ]; then
        count=$(echo "$violators" | grep -c .)
        pod_list="$violators"
    fi

    if [ "$count" -eq 0 ]; then
        log_pass "$control_id: Không có pod nào vi phạm."
        report_add "$control_id" "PASS" "0 pods vi phạm (đã kiểm tra $USER_PODS user pods)"
    else
        log_fail "$control_id: Phát hiện $count pod(s) vi phạm!"

        # In chi tiết từng pod vi phạm (tối đa 10)
        local shown=0
        while IFS= read -r pod_info; do
            if [ $shown -lt 10 ]; then
                log_fail "  ↳ $pod_info"
                ((shown++))
            fi
        done <<< "$pod_list"
        if [ $count -gt 10 ]; then
            log_warn "  ... và $((count - 10)) pod(s) khác."
        fi

        # Lưu report với danh sách pods (rút gọn nếu quá dài)
        local detail_pods
        if [ $count -le 3 ]; then
            detail_pods=$(echo "$pod_list" | tr '\n' ', ' | sed 's/,$//')
        else
            detail_pods=$(echo "$pod_list" | head -3 | tr '\n' ', ' | sed 's/,$//')
            detail_pods="${detail_pods} (+$((count-3)) khác)"
        fi
        report_add "$control_id" "FAIL" "$count pods vi phạm: $detail_pods"
    fi
}


# =====================================================================
# 4.2.1 - Minimize admission of privileged containers
# ---------------------------------------------------------------------
# Kiểm tra: containers[].securityContext.privileged != true
# Pod chạy privileged có toàn quyền trên host → bypass mọi isolation.
# =====================================================================
check_pod_security \
    "4.2.1" \
    "Minimize admission of privileged containers" \
    '[.items[] | select(.metadata.namespace | test($regex) | not) |
      . as $pod |
      .spec.containers[]? |
      select(.securityContext.privileged == true) |
      "\($pod.metadata.namespace)/\($pod.metadata.name) → container: \(.name)"
    ] | .[]' \
    "Container privileged=true có toàn quyền root trên host, bypass mọi Linux security (namespaces, cgroups, seccomp)"


# =====================================================================
# 4.2.2 - Minimize containers sharing host PID namespace
# ---------------------------------------------------------------------
# Kiểm tra: spec.hostPID != true
# hostPID cho phép container thấy toàn bộ processes trên host
# → có thể kill processes, đọc /proc, gắn debugger.
# =====================================================================
check_pod_security \
    "4.2.2" \
    "Minimize containers sharing host PID namespace" \
    '[.items[] | select(.metadata.namespace | test($regex) | not) |
      select(.spec.hostPID == true) |
      "\(.metadata.namespace)/\(.metadata.name)"
    ] | .[]' \
    "hostPID=true cho phép container thấy và tương tác với tất cả process trên host node"


# =====================================================================
# 4.2.3 - Minimize containers sharing host IPC namespace
# ---------------------------------------------------------------------
# Kiểm tra: spec.hostIPC != true
# hostIPC cho phép container đọc shared memory trên host
# → có thể đọc dữ liệu nhạy cảm từ processes khác.
# =====================================================================
check_pod_security \
    "4.2.3" \
    "Minimize containers sharing host IPC namespace" \
    '[.items[] | select(.metadata.namespace | test($regex) | not) |
      select(.spec.hostIPC == true) |
      "\(.metadata.namespace)/\(.metadata.name)"
    ] | .[]' \
    "hostIPC=true cho phép container truy cập shared memory segment của host (có thể đọc data nhạy cảm)"


# =====================================================================
# 4.2.4 - Minimize containers sharing host network namespace
# ---------------------------------------------------------------------
# Kiểm tra: spec.hostNetwork != true
# hostNetwork=true cho container sử dụng network stack của host
# → có thể sniff traffic, bind privileged ports, bypass NetworkPolicy.
# =====================================================================
check_pod_security \
    "4.2.4" \
    "Minimize containers sharing host network namespace" \
    '[.items[] | select(.metadata.namespace | test($regex) | not) |
      select(.spec.hostNetwork == true) |
      "\(.metadata.namespace)/\(.metadata.name)"
    ] | .[]' \
    "hostNetwork=true cho phép container sniff traffic, bind port <1024, bypass hoàn toàn NetworkPolicy"


# =====================================================================
# 4.2.5 - Minimize containers with allowPrivilegeEscalation
# ---------------------------------------------------------------------
# Kiểm tra: containers[].securityContext.allowPrivilegeEscalation != true
#
# CHÚ Ý QUAN TRỌNG:
#   - Mặc định Kubernetes set allowPrivilegeEscalation = true nếu không khai báo
#   - CIS khuyến nghị phải SET TƯỜNG MINH = false
#   - Nên kiểm tra cả trường hợp = true VÀ chưa set (null)
# =====================================================================
check_pod_security \
    "4.2.5" \
    "Minimize containers with allowPrivilegeEscalation" \
    '[.items[] | select(.metadata.namespace | test($regex) | not) |
      . as $pod |
      .spec.containers[]? |
      select(
        .securityContext.allowPrivilegeEscalation == true or
        (.securityContext.allowPrivilegeEscalation == null and (.securityContext.privileged // false) == false)
      ) |
      "\($pod.metadata.namespace)/\($pod.metadata.name) → container: \(.name)"
    ] | .[]' \
    "allowPrivilegeEscalation=true (hoặc không set) cho phép process con được quyền cao hơn cha (vd: SUID, ptrace)"


# =====================================================================
# KẾT THÚC - IN VÀ LƯU BÁO CÁO
# =====================================================================
report_print_summary

# Lưu báo cáo vào thư mục chung của dự án
REPORT_DIR="$SCRIPT_DIR/../../../report"
report_save_json "$REPORT_DIR"
report_save_html "$REPORT_DIR"
