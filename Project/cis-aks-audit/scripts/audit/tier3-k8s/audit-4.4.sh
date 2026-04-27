#!/bin/bash
# =====================================================================
# audit-4.4.sh - CIS AKS Benchmark Controls 4.4.1 & 4.4.2
#
# Controls:
#   4.4.1 - CNI phải hỗ trợ NetworkPolicy (Azure-level check)
#   4.4.2 - Tất cả Namespace phải có NetworkPolicy được định nghĩa
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

report_init "4.4" "Network Policies and CNI"

# ─────────────────────────────────────────
#  4.4.1 - Ensure that the CNI in use supports Network Policies
#
#  Kubenet không hỗ trợ NetworkPolicy đầy đủ.
#  Azure CNI ("azure") kết hợp với Calico/Azure policy mới đảm bảo.
#
#  Kiểm tra: networkProfile.networkPlugin + networkProfile.networkPolicy
#  Mong đợi: plugin = "azure" VÀ policy = "calico" hoặc "azure"
# ─────────────────────────────────────────
check_4_4_1() {
    log_section "4.4.1 - Ensure CNI supports Network Policies"
    log_info "Lý do: kubenet không hỗ trợ đầy đủ NetworkPolicy → không kiểm soát được traffic"

    load_aks_json

    if [ -z "$AKS_JSON" ]; then
        log_warn "4.4.1: Không lấy được thông tin cluster"
        report_add "4.4.1" "WARN" "Khong lay duoc thong tin cluster"
        return
    fi

    local network_plugin
    network_plugin=$(echo "$AKS_JSON" | jq -r '.networkProfile.networkPlugin // "none"')

    local network_policy
    network_policy=$(echo "$AKS_JSON" | jq -r '.networkProfile.networkPolicy // "none"')

    log_info "networkPlugin = $network_plugin"
    log_info "networkPolicy = $network_policy"

    if [[ "$network_plugin" =~ ^(azure|cilium)$ ]] && [[ "$network_policy" =~ ^(calico|azure|cilium)$ ]]; then
        log_pass "4.4.1: CNI = $network_plugin + policy engine = $network_policy ✓"
        report_add "4.4.1" "PASS" "networkPlugin=$network_plugin, networkPolicy=$network_policy"
    elif [[ "$network_plugin" =~ ^(azure|cilium)$ ]] && [ "$network_policy" = "none" ]; then
        log_fail "4.4.1: CNI bật nhưng NetworkPolicy engine chưa được cấu hình ✗"
        report_add "4.4.1" "FAIL" "networkPlugin=$network_plugin nhung networkPolicy=none"
    elif [ "$network_plugin" = "kubenet" ]; then
        log_fail "4.4.1: kubenet không hỗ trợ đầy đủ NetworkPolicy ✗"
        report_add "4.4.1" "FAIL" "networkPlugin=kubenet (khong ho tro NetworkPolicy day du)"
    else
        log_warn "4.4.1: Cấu hình không xác định: plugin=$network_plugin, policy=$network_policy"
        report_add "4.4.1" "WARN" "networkPlugin=$network_plugin, networkPolicy=$network_policy"
    fi
}

# ─────────────────────────────────────────
#  4.4.2 - Ensure that all Namespaces have Network Policies defined
#
#  Namespace không có NetworkPolicy → mọi pod trong đó đều
#  có thể giao tiếp tự do với nhau → lateral movement dễ dàng.
#
#  Kiểm tra: kubectl get networkpolicy -n <namespace>
#  Mong đợi: mỗi namespace user-defined có ít nhất 1 NetworkPolicy
#
#  Bỏ qua: kube-system, kube-public, kube-node-lease,
#           calico-system, calico-apiserver, gatekeeper-system
# ─────────────────────────────────────────
check_4_4_2() {
    log_section "4.4.2 - Ensure all Namespaces have Network Policies defined"
    log_info "Lý do: Namespace không có NetworkPolicy → pods thông nhau → lateral movement"

    # Lấy danh sách namespace, bỏ qua system namespaces
    local all_ns
    all_ns=$(kubectl get ns --no-headers -o custom-columns=':metadata.name' 2>/dev/null \
        | grep -vE '^(kube-system|kube-public|kube-node-lease|calico-system|calico-apiserver|gatekeeper-system|azure-arc)$')

    if [ -z "$all_ns" ]; then
        log_warn "4.4.2: Không lấy được danh sách namespaces"
        report_add "4.4.2" "WARN" "Khong lay duoc danh sach namespaces"
        return
    fi

    local fail_list=""
    local pass_count=0
    local fail_count=0

    while IFS= read -r ns; do
        [ -z "$ns" ] && continue
        local np_count
        np_count=$(kubectl get networkpolicy -n "$ns" --no-headers 2>/dev/null | grep -c .)
        if [ "$np_count" -eq 0 ]; then
            log_fail "  ✗ Namespace '$ns': không có NetworkPolicy"
            fail_list="${fail_list}${ns} "
            ((fail_count++))
        else
            log_pass "  ✓ Namespace '$ns': $np_count NetworkPolicy"
            ((pass_count++))
        fi
    done <<< "$all_ns"

    log_info "Tổng: $pass_count namespace OK | $fail_count namespace thiếu NetworkPolicy"

    if [ "$fail_count" -eq 0 ]; then
        report_add "4.4.2" "PASS" "Tat ca $pass_count namespace co NetworkPolicy"
    else
        report_add "4.4.2" "FAIL" "$fail_count namespace thieu NetworkPolicy: ${fail_list% }"
    fi
}

# ── MAIN ─────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "${C_BLUE}  CIS AKS Benchmark v1.8.0 - Section 4.4              ${C_RESET}"
    echo -e "${C_BLUE}  Network Policies and CNI                             ${C_RESET}"
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "  Thời gian: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    for tool in az kubectl jq; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${C_RED}[ERROR]${C_RESET} '$tool' chưa cài. Vui lòng cài trước."
            exit 1
        fi
    done

    if ! az account show &>/dev/null; then
        echo -e "${C_RED}[ERROR]${C_RESET} Chưa đăng nhập Azure. Chạy: az login"
        exit 1
    fi

    get_cluster_info || exit 1

    echo ""
    check_4_4_1
    check_4_4_2

    report_print_summary
    local report_dir="$SCRIPT_DIR/../../../report"
    report_save_json "$report_dir"
    report_save_html "$report_dir"
}

main
