#!/bin/bash
# =====================================================================
# audit-3.1.sh - CIS AKS Benchmark v1.8.0 - Section 3.1
# Worker Node Configuration - File Permissions
# =====================================================================

# Lấy đường dẫn tuyệt đối của thư mục chứa script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

log_section "CIS AKS Benchmark 3.1 - Worker Node File Permissions"
report_init "3.1" "Worker Node Configuration - File Permissions"

# 1. Khởi tạo kết nối Node
NODE=$(get_nodes | head -1)
if [ -z "$NODE" ]; then
    log_fail "Không tìm thấy node nào đang chạy."
    exit 1
fi
node_setup "$NODE" || exit 1

# 2. Gộp tất cả các lệnh kiểm tra vào 1 khối (Tối ưu tốc độ cực đại)
log_info "Đang đọc toàn bộ cấu hình file trên node (1 lần duy nhất)..."
MULTI_CMD=$(cat << 'EOF'
# Tìm đường dẫn kubeconfig thực tế
K_PATH=$(ps -ef | grep kubelet | grep -oP '(?<=--kubeconfig=)[^ ]+' | head -1)
[ -z "$K_PATH" ] && K_PATH="/var/lib/kubelet/kubeconfig"

# Kiểm tra Kubeconfig
if [ -f "$K_PATH" ]; then
    K_EXISTS="yes"
    K_PERM=$(stat -c '%a' "$K_PATH")
    K_OWNER=$(stat -c '%U:%G' "$K_PATH")
else
    K_EXISTS="no"
fi

# Kiểm tra azure.json
A_PATH="/etc/kubernetes/azure.json"
if [ -f "$A_PATH" ]; then
    A_EXISTS="yes"
    A_PERM=$(stat -c '%a' "$A_PATH")
    A_OWNER=$(stat -c '%U:%G' "$A_PATH")
else
    A_EXISTS="no"
fi

# In kết quả ra dạng Key=Value
echo "K_PATH=$K_PATH"
echo "K_EXISTS=$K_EXISTS"
echo "K_PERM=$K_PERM"
echo "K_OWNER=$K_OWNER"
echo "A_PATH=$A_PATH"
echo "A_EXISTS=$A_EXISTS"
echo "A_PERM=$A_PERM"
echo "A_OWNER=$A_OWNER"
EOF
)

# Thực thi lệnh gộp
RAW_OUTPUT=$(node_exec "$MULTI_CMD")

# Hàm parse dữ liệu từ output
get_val() { echo "$RAW_OUTPUT" | grep "^$1=" | cut -d'=' -f2 | tr -d '\r'; }

K_PATH=$(get_val "K_PATH")
K_EXISTS=$(get_val "K_EXISTS")
K_PERM=$(get_val "K_PERM")
K_OWNER=$(get_val "K_OWNER")
A_PATH=$(get_val "A_PATH")
A_EXISTS=$(get_val "A_EXISTS")
A_PERM=$(get_val "A_PERM")
A_OWNER=$(get_val "A_OWNER")


# ==========================================
# HÀM KIỂM TRA CHUNG KÈM REMEDIATION
# ==========================================
evaluate_perm() {
    local control=$1
    local name=$2
    local path=$3
    local exists=$4
    local perm=$5
    local max_perm=644

    log_section "$control - Permissions cho $name"
    
    if [ "$exists" != "yes" ]; then
        log_warn "File không tồn tại: $path"
        report_add "$control" "N/A" "File không tồn tại"
        return
    fi

    log_info "Current: $perm | Expected: <= $max_perm"

    # Kiểm tra quyền có <= 644 không (vd: 644, 640, 600)
    if [[ "$perm" =~ ^[0-6][0-4][0-4]$ ]]; then
        log_pass "Quyền hợp lệ."
        report_add "$control" "PASS" "Perm: $perm"
    else
        log_fail "Quyền không hợp lệ!"
        if ask_remediate "Sửa quyền file $name về $max_perm? [Y/n]: "; then
            node_exec "chmod $max_perm $path"
            log_info "Đã chạy lệnh vá lỗi."
            report_add "$control" "FAIL" "Perm: $perm -> $max_perm" "true"
        else
            report_add "$control" "FAIL" "Perm: $perm (yêu cầu <= $max_perm)"
        fi
    fi
}

evaluate_owner() {
    local control=$1
    local name=$2
    local path=$3
    local exists=$4
    local owner=$5
    local expected="root:root"

    log_section "$control - Ownership cho $name"
    
    if [ "$exists" != "yes" ]; then
        report_add "$control" "N/A" "File không tồn tại"
        return
    fi

    log_info "Current: $owner | Expected: $expected"

    if [ "$owner" == "$expected" ]; then
        log_pass "Chủ sở hữu hợp lệ."
        report_add "$control" "PASS" "Owner: $owner"
    else
        log_fail "Chủ sở hữu không hợp lệ!"
        if ask_remediate "Sửa chủ sở hữu $name thành $expected? [Y/n]: "; then
            node_exec "chown $expected $path"
            log_info "Đã chạy lệnh vá lỗi."
            report_add "$control" "FAIL" "Owner: $owner -> $expected" "true"
        else
            report_add "$control" "FAIL" "Owner: $owner (yêu cầu $expected)"
        fi
    fi
}


# 3. Đánh giá từng tiêu chí
evaluate_perm  "3.1.1" "kubeconfig" "$K_PATH" "$K_EXISTS" "$K_PERM"
evaluate_owner "3.1.2" "kubeconfig" "$K_PATH" "$K_EXISTS" "$K_OWNER"
evaluate_perm  "3.1.3" "azure.json" "$A_PATH" "$A_EXISTS" "$A_PERM"
evaluate_owner "3.1.4" "azure.json" "$A_PATH" "$A_EXISTS" "$A_OWNER"

# 4. Dọn dẹp & Xuất báo cáo
node_cleanup
report_print_summary

# Lưu báo cáo vào thư mục chung của dự án
REPORT_DIR="$SCRIPT_DIR/../../../report"
report_save_json "$REPORT_DIR"
report_save_html "$REPORT_DIR"