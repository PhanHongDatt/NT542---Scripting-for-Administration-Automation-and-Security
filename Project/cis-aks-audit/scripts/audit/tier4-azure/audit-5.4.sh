#!/bin/bash
# ============================================================
#  audit-5.4.sh - CIS AKS Benchmark v1.8.0 - Section 5.4.3 + 5.4.4
#  Azure-level Security Controls
#
#  Controls:
#    5.4.3 - Nodes phải là Private Nodes (không có public IP)
#    5.4.4 - Network Policy phải được bật
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

report_init "5.4.3+5.4.4" "Azure-level Network Security"


# ─────────────────────────────────────────
#  5.4.3 - Ensure clusters are created with Private Nodes
#
#  Private Nodes = worker nodes không có public IP.
#  Nodes có public IP → attacker có thể SSH thẳng vào.
#
#  Kiểm tra: agentPoolProfiles[].enableNodePublicIP
#  Mong đợi: false (không có public IP)
# ─────────────────────────────────────────
check_5_4_3() {
    log_section "5.4.3 - Ensure clusters are created with Private Nodes"
    log_info "Lý do: Node có public IP → attacker có thể tấn công trực tiếp từ internet"

    load_aks_json

    if [ -z "$AKS_JSON" ]; then
        log_warn "5.4.3: Không lấy được thông tin cluster"
        report_add "5.4.3" "WARN" "Khong lay duoc thong tin cluster"
        return
    fi

    # Kiểm tra tất cả node pools
    # jq lấy tất cả giá trị enableNodePublicIP từ mảng agentPoolProfiles
    local public_ip_pools
    public_ip_pools=$(echo "$AKS_JSON" | \
        jq '[.agentPoolProfiles[] | select(.enableNodePublicIP == true) | .name] | join(", ")' \
        2>/dev/null)

    local public_ip_count
    public_ip_count=$(echo "$AKS_JSON" | \
        jq '[.agentPoolProfiles[] | select(.enableNodePublicIP == true)] | length' \
        2>/dev/null)

    log_info "Node pools có public IP: $public_ip_count"
    [ "$public_ip_count" -gt 0 ] && log_info "Tên pools: $public_ip_pools"

    if [ "$public_ip_count" -eq 0 ] 2>/dev/null; then
        log_pass "5.4.3: Tất cả node pools có enableNodePublicIP = false ✓"
        report_add "5.4.3" "PASS" "Tat ca nodes khong co public IP"
    else
        log_fail "5.4.3: $public_ip_count node pool(s) có public IP: $public_ip_pools ✗"
        log_fail "       Nodes có public IP làm tăng attack surface đáng kể!"
        report_add "5.4.3" "FAIL" "$public_ip_count pool co public IP: $public_ip_pools"

        # Lưu ý: Không thể tắt public IP của node pool đang chạy mà không recreate
        log_warn "Remediation: Cần tạo lại node pool với enableNodePublicIP=false"
        log_warn "Lệnh: az aks nodepool update (không hỗ trợ đổi public IP trực tiếp)"
        log_warn "Cách đúng: terraform apply với enable_node_public_ip = false"
    fi
}

# ─────────────────────────────────────────
#  5.4.4 - Ensure Network Policy is Enabled
#
#  Không có Network Policy = mọi pod nói chuyện với mọi pod.
#  Attacker chiếm 1 pod → lateral movement dễ dàng.
#
#  Kiểm tra: networkProfile.networkPolicy
#  Mong đợi: "azure" hoặc "calico" (không phải null/none)
# ─────────────────────────────────────────
check_5_4_4() {
    log_section "5.4.4 - Ensure Network Policy is Enabled and set as appropriate"
    log_info "Lý do: Không có Network Policy → mọi pod thông nhau → lateral movement dễ dàng"

    load_aks_json

    if [ -z "$AKS_JSON" ]; then
        log_warn "5.4.4: Không lấy được thông tin cluster"
        report_add "5.4.4" "WARN" "Khong lay duoc thong tin cluster"
        return
    fi

    # Lấy network plugin và network policy
    local network_plugin
    network_plugin=$(echo "$AKS_JSON" | \
        jq -r '.networkProfile.networkPlugin // "none"' 2>/dev/null)

    local network_policy
    network_policy=$(echo "$AKS_JSON" | \
        jq -r '.networkProfile.networkPolicy // "none"' 2>/dev/null)

    log_info "networkPlugin = $network_plugin"
    log_info "networkPolicy = $network_policy"

    if [ "$network_policy" = "none" ] || [ "$network_policy" = "null" ] || [ -z "$network_policy" ]; then
        log_fail "5.4.4: networkPolicy = none (chưa bật) ✗"
        log_fail "       Cluster không có cơ chế kiểm soát traffic giữa các pods!"

        log_warn "Remediation: Network Policy không thể bật sau khi tạo cluster."
        log_warn "Cần recreate cluster với network_policy = 'azure' hoặc 'calico'"
        log_warn "Trong terraform/variables.tf: đổi network_policy = 'calico'"
        report_add "5.4.4" "FAIL" "networkPolicy = none (chua bat)"
    elif [ "$network_policy" = "azure" ] || [ "$network_policy" = "calico" ]; then
        log_pass "5.4.4: networkPolicy = $network_policy ✓"

        # Kiểm tra thêm xem có NetworkPolicy objects trong cluster không
        local np_count
        np_count=$(kubectl get networkpolicy --all-namespaces \
            --no-headers 2>/dev/null | wc -l)
        log_info "Số NetworkPolicy objects trong cluster: $np_count"

        if [ "$np_count" -eq 0 ]; then
            log_warn "Network Policy engine bật nhưng chưa có policy nào được định nghĩa!"
            report_add "5.4.4" "PASS" "networkPolicy = $network_policy (engine bat, nhung chua co policy objects)"
        else
            report_add "5.4.4" "PASS" "networkPolicy = $network_policy ($np_count policy objects)"
        fi
    else
        log_warn "5.4.4: networkPolicy = $network_policy (không rõ)"
        report_add "5.4.4" "WARN" "networkPolicy = $network_policy"
    fi
}

# ── MAIN ─────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "${C_BLUE}  CIS AKS Benchmark v1.8.0 - Section 5.4.3 + 5.4.4    ${C_RESET}"
    echo -e "${C_BLUE}  Azure-level Network Security                         ${C_RESET}"
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "  Thời gian: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Kiểm tra công cụ cần thiết
    for tool in az kubectl jq; do
        if ! command -v "$tool" &>/dev/null; then
            echo -e "${C_RED}[ERROR]${C_RESET} '$tool' chưa cài. Vui lòng cài trước."
            exit 1
        fi
    done

    # Kiểm tra đã đăng nhập Azure chưa
    if ! az account show &>/dev/null; then
        echo -e "${C_RED}[ERROR]${C_RESET} Chưa đăng nhập Azure. Chạy: az login"
        exit 1
    fi

    # Lấy thông tin cluster
    get_cluster_info || exit 1

    echo ""
    check_5_4_3
    check_5_4_4

    report_print_summary
    local report_dir="$SCRIPT_DIR/../../../report"
    report_save_json "$report_dir"
    report_save_html "$report_dir"
}

main