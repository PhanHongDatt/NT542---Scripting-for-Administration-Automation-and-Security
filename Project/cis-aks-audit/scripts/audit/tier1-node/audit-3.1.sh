#!/bin/bash
# ============================================================
#  audit-3.1.sh - CIS AKS Benchmark v1.8.0 - Section 3.1
#  Worker Node Configuration - File Permissions
#
#  Controls:
#    3.1.1 - kubeconfig permissions <= 644
#    3.1.2 - kubeconfig ownership = root:root
#    3.1.3 - azure.json permissions <= 644
#    3.1.4 - azure.json ownership = root:root
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

report_init "3.1" "Worker Node File Permissions"

# ─────────────────────────────────────────
#  HÀM: Lấy path kubeconfig thực tế từ kubelet process
#  Kubelet được start với --kubeconfig=/path → tìm động
#  thay vì hardcode để tránh sai trên các phiên bản AKS khác nhau
# ─────────────────────────────────────────
get_kubeconfig_path() {
    local path
    # Lấy giá trị --kubeconfig từ command line của kubelet trên node hiện tại.
    path=$(node_exec "ps -ef | grep -oP '(?<= )--kubeconfig=\S+' | cut -d= -f2 | head -1")
    if [ -n "$path" ] && [ "$path" != "ERROR" ] && [ "$path" != "NO_POD" ]; then
        echo "$path"
    else
        # Fallback an toàn nếu không parse được process args.
        echo "/var/lib/kubelet/kubeconfig"
    fi
}

# ─────────────────────────────────────────
#  HÀM: Kiểm tra permission của file
#  $1=control_id  $2=file_path  $3=max_perm (vd: 644)
# ─────────────────────────────────────────
check_file_permission() {
    local control_id=$1 file_path=$2 max_perm=$3

    log_section "$control_id - Kiểm tra permission: $file_path"

    # Với kubeconfig: tìm path thực từ kubelet args
    local actual_path="$file_path"
    if [[ "$file_path" == *"kubeconfig"* ]]; then
        actual_path=$(get_kubeconfig_path)
    fi

    # Kiểm tra file có tồn tại không
    local exists
    exists=$(node_exec "[ -f '$actual_path' ] && echo yes || echo no")
    if [ "$exists" != "yes" ]; then
        log_warn "$control_id: File không tồn tại: $actual_path"
        report_add "$control_id" "WARN" "File khong ton tai: $actual_path"
        return
    fi

    # stat -c %a → permission dạng số (600, 644, 755...)
    local current_perm
    current_perm=$(node_exec "stat -c %a '$actual_path'")

    if [ -z "$current_perm" ] || [ "$current_perm" = "ERROR" ] || [ "$current_perm" = "NO_POD" ]; then
        log_warn "$control_id: Không đọc được permission"
        report_add "$control_id" "WARN" "Khong doc duoc permission"
        return
    fi

    log_info "File: $actual_path | Permission: $current_perm | Yêu cầu: <= $max_perm"

    if [ "$current_perm" -le "$max_perm" ] 2>/dev/null; then
        log_pass "$control_id: Permission $current_perm <= $max_perm ✓"
        report_add "$control_id" "PASS" "Permission: $current_perm"
    else
        log_fail "$control_id: Permission $current_perm > $max_perm ✗"
        # Cho phép người vận hành quyết định tự remediate ngay trong phiên audit.
        if ask_remediate "Sửa permission về $max_perm? [Y/n]: "; then
            node_exec "chmod $max_perm '$actual_path'"
            local new_perm
            new_perm=$(node_exec "stat -c %a '$actual_path'")
            log_info "Đã sửa: $current_perm → $new_perm"
            report_add "$control_id" "FAIL" "Permission: $current_perm → $new_perm" "true"
        else
            report_add "$control_id" "FAIL" "Permission: $current_perm (can <= $max_perm)"
        fi
    fi
}

# ─────────────────────────────────────────
#  HÀM: Kiểm tra ownership của file
#  $1=control_id  $2=file_path  $3=expected (vd: "root:root")
# ─────────────────────────────────────────
check_file_ownership() {
    local control_id=$1 file_path=$2 expected=$3

    log_section "$control_id - Kiểm tra ownership: $file_path"

    local actual_path="$file_path"
    if [[ "$file_path" == *"kubeconfig"* ]]; then
        actual_path=$(get_kubeconfig_path)
    fi

    local exists
    exists=$(node_exec "[ -f '$actual_path' ] && echo yes || echo no")
    if [ "$exists" != "yes" ]; then
        log_warn "$control_id: File không tồn tại: $actual_path"
        report_add "$control_id" "WARN" "File khong ton tai: $actual_path"
        return
    fi

    # stat -c %U:%G → "user:group" (vd: "root:root")
    local current_owner
    current_owner=$(node_exec "stat -c %U:%G '$actual_path'")

    if [ -z "$current_owner" ] || [ "$current_owner" = "ERROR" ] || [ "$current_owner" = "NO_POD" ]; then
        log_warn "$control_id: Không đọc được ownership"
        report_add "$control_id" "WARN" "Khong doc duoc ownership"
        return
    fi

    log_info "File: $actual_path | Ownership: $current_owner | Yêu cầu: $expected"

    if [ "$current_owner" = "$expected" ]; then
        log_pass "$control_id: Ownership $current_owner = $expected ✓"
        report_add "$control_id" "PASS" "Ownership: $current_owner"
    else
        log_fail "$control_id: Ownership $current_owner ≠ $expected ✗"
        # Nếu người dùng đồng ý, cập nhật owner/group và ghi lại trạng thái đã remediate.
        if ask_remediate "Sửa ownership về $expected? [Y/n]: "; then
            node_exec "chown $expected '$actual_path'"
            local new_owner
            new_owner=$(node_exec "stat -c %U:%G '$actual_path'")
            log_info "Đã sửa: $current_owner → $new_owner"
            report_add "$control_id" "FAIL" "Ownership: $current_owner → $new_owner" "true"
        else
            report_add "$control_id" "FAIL" "Ownership: $current_owner (can $expected)"
        fi
    fi
}

# ── MAIN ─────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "${C_BLUE}  CIS AKS Benchmark v1.8.0 - Section 3.1              ${C_RESET}"
    echo -e "${C_BLUE}  Worker Node Configuration - File Permissions         ${C_RESET}"
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "  Thời gian: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    local nodes
    nodes=$(get_nodes)
    if [ -z "$nodes" ]; then
        echo -e "${C_RED}[ERROR]${C_RESET} Không tìm thấy node! Kiểm tra: kubectl get nodes"
        exit 1
    fi

    # Chạy audit tuần tự theo từng node để cô lập log/report theo ngữ cảnh node.
    log_info "Tìm thấy $(echo "$nodes" | wc -l) node(s)"

    for node in $nodes; do
        echo ""
        echo -e "${C_BLUE}╔══════════════════════════════════════════╗${C_RESET}"
        echo -e "${C_BLUE}║  NODE: $node${C_RESET}"
        echo -e "${C_BLUE}╚══════════════════════════════════════════╝${C_RESET}"

        # Không thiết lập được context node thì bỏ qua node đó và tiếp tục node còn lại.
        node_setup "$node" || { log_warn "Bỏ qua node $node."; continue; }

        # Mapping control CIS 3.1.1-3.1.4 vào từng hàm check tương ứng.
        check_file_permission "3.1.1" "/var/lib/kubelet/kubeconfig" 644
        check_file_ownership  "3.1.2" "/var/lib/kubelet/kubeconfig" "root:root"
        check_file_permission "3.1.3" "/etc/kubernetes/azure.json"  644
        check_file_ownership  "3.1.4" "/etc/kubernetes/azure.json"  "root:root"

        node_cleanup
    done

    # Tổng hợp kết quả và xuất cả JSON lẫn HTML để tiện CI/CD và đọc thủ công.
    report_print_summary
    local report_dir="$SCRIPT_DIR/../../../report"
    report_save_json "$report_dir"
    report_save_html "$report_dir"
}

main