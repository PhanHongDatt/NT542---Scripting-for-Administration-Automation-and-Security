#!/bin/bash
# ============================================================
#  audit-5.1.sh - CIS AKS Benchmark v1.8.0 - Section 5.1 + 5.4.1
#  Azure-level Security Controls
#
#  Controls:
#    5.1.1 - Microsoft Defender for Containers phải bật
#    5.1.2 - Diagnostic Setting phải bật để capture logs
#    5.1.3 - Azure Policy Add-on phải được cài đặt
#    5.4.1 - API Server phải giới hạn IP (authorizedIpRanges)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

report_init "5.1+5.4.1" "Azure-level Security Controls"


# ─────────────────────────────────────────
#  5.1.1 - Microsoft Defender for Containers
#
#  Defender quét lỗ hổng container images và phát hiện
#  runtime threats. Thiếu = không có security monitoring.
#
#  Kiểm tra: az security pricing show --name Containers
#  Mong đợi: pricingTier = "Standard" (bật)
#            pricingTier = "Free"     (tắt → FAIL)
# ─────────────────────────────────────────
check_5_1_1() {
    log_section "5.1.1 - Ensure Microsoft Defender for Containers bật"
    log_info "Lý do: Defender quét lỗ hổng container image, phát hiện runtime threats"

    local defender_json
    defender_json=$(az security pricing show --name "Containers" --output json 2>/dev/null)

    if [ -z "$defender_json" ] || [ "$defender_json" = "null" ]; then
        log_warn "5.1.1: Không lấy được thông tin Defender (cần quyền Security Reader)"
        report_add "5.1.1" "WARN" "Khong lay duoc thong tin Defender - thieu quyen"
        return
    fi

    local pricing_tier
    pricing_tier=$(echo "$defender_json" | jq -r '.pricingTier' 2>/dev/null)
    log_info "Defender for Containers pricingTier = $pricing_tier"

    if [ "$pricing_tier" = "Standard" ]; then
        log_pass "5.1.1: Defender for Containers = Standard (đang bật) ✓"
        report_add "5.1.1" "PASS" "Defender pricingTier = Standard"
    elif [ "$pricing_tier" = "Free" ]; then
        log_fail "5.1.1: Defender for Containers = Free (đang tắt) ✗"

        if ask_remediate "Bật Microsoft Defender for Containers? [Y/n]: "; then
            az security pricing create \
                --name "Containers" \
                --tier "Standard" \
                --output none 2>/dev/null

            local new_tier
            new_tier=$(az security pricing show \
                --name "Containers" --query pricingTier -o tsv 2>/dev/null)
            log_info "Đã bật Defender: Free → $new_tier"
            report_add "5.1.1" "FAIL" "Defender: Free → $new_tier (da bat)" "true"
        else
            report_add "5.1.1" "FAIL" "Defender pricingTier = Free (tat)"
        fi
    else
        log_warn "5.1.1: pricingTier = $pricing_tier (không xác định)"
        report_add "5.1.1" "WARN" "pricingTier = $pricing_tier"
    fi
}

# ─────────────────────────────────────────
#  5.1.2 - Ensure Diagnostic Setting is enabled to capture all logs
#
#  Diagnostic Settings cho phép đẩy logs của Control Plane (API Server,
#  Audit Logs, v.v.) vào Log Analytics để giám sát.
#
#  Kiểm tra: az monitor diagnostic-settings list
#  Mong đợi: Ít nhất 1 setting đang bật và đẩy log vào workspace.
# ─────────────────────────────────────────
check_5_1_2() {
    log_section "5.1.2 - Ensure Diagnostic Setting is enabled to capture all logs"
    log_info "Lý do: Thiếu Diagnostic Settings = mất dấu vết các hành động trên Control Plane"

    # Lấy resource ID của cluster
    local cluster_id
    cluster_id=$(echo "$AKS_JSON" | jq -r '.id')

    local diag_json
    diag_json=$(az monitor diagnostic-settings list --resource "$cluster_id" --output json 2>/dev/null)

    if [ -z "$diag_json" ] || [ "$diag_json" = "[]" ]; then
        log_fail "5.1.2: Chưa có Diagnostic Setting nào được cấu hình ✗"
        report_add "5.1.2" "FAIL" "Chua co Diagnostic Setting nao duoc cau hinh"
    else
        local workspace_id
        workspace_id=$(echo "$diag_json" | jq -r '.[0].workspaceId // ""')

        if [ -n "$workspace_id" ] && [ "$workspace_id" != "null" ]; then
            log_pass "5.1.2: Đã tìm thấy Diagnostic Setting trỏ về workspace: $workspace_id ✓"
            report_add "5.1.2" "PASS" "Diagnostic Setting dang bat"
        else
            log_fail "5.1.2: Diagnostic Setting tồn tại nhưng chưa trỏ về Log Analytics Workspace ✗"
            report_add "5.1.2" "FAIL" "Diagnostic Setting chua tro ve Workspace"
        fi
    fi
}

# ─────────────────────────────────────────
#  5.1.3 - Ensure Azure Policy Add-on for Kubernetes is installed
#
#  Azure Policy Add-on cho phép quản lý và thực thi các chính sách
#  bảo mật (như chặn pod chạy root) tập trung từ Azure Policy.
#
#  Kiểm tra: addonProfiles.azurepolicy.enabled
#  Mong đợi: true
# ─────────────────────────────────────────
check_5_1_3() {
    log_section "5.1.3 - Ensure Azure Policy Add-on for Kubernetes is installed"
    log_info "Lý do: Azure Policy giúp thực thi các tiêu chuẩn bảo mật (PSP/PSA) tập trung"

    load_aks_json

    local policy_enabled
    policy_enabled=$(echo "$AKS_JSON" | jq -r '.addonProfiles.azurepolicy.enabled // "false"')

    log_info "Azure Policy Add-on enabled = $policy_enabled"

    if [ "$policy_enabled" == "true" ]; then
        log_pass "5.1.3: Azure Policy Add-on đang bật ✓"
        report_add "5.1.3" "PASS" "Azure Policy Add-on dang bat"
    else
        log_fail "5.1.3: Azure Policy Add-on chưa được cài đặt ✗"
        
        if ask_remediate "Bật Azure Policy Add-on cho cluster? [Y/n]: "; then
            log_info "Đang bật Azure Policy Add-on (có thể mất vài phút)..."
            az aks enable-addons \
                --addons azure-policy \
                --name "$CLUSTER_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --output none 2>/dev/null
            
            log_pass "Đã yêu cầu bật Azure Policy Add-on ✓"
            report_add "5.1.3" "FAIL" "Azure Policy Add-on: Disabled -> Enabled (da sua)" "true"
        else
            report_add "5.1.3" "FAIL" "Azure Policy Add-on chua bat"
        fi
    fi
}

# ─────────────────────────────────────────
#  5.4.1 - Restrict Access to the Control Plane Endpoint
#
#  API Server là "cửa vào" của Kubernetes. Nếu để public
#  (authorizedIpRanges rỗng) → attacker có thể tấn công.
#  Mong đợi: authorizedIpRanges KHÔNG rỗng và KHÔNG chứa 0.0.0.0/0
# ─────────────────────────────────────────
check_5_4_1() {
    log_section "5.4.1 - Restrict Access to the Control Plane Endpoint"
    log_info "Lý do: API Server public cho phép attacker toàn cầu brute-force cluster"

    load_aks_json

    if [ -z "$AKS_JSON" ]; then
        log_warn "5.4.1: Không lấy được thông tin cluster"
        report_add "5.4.1" "WARN" "Khong lay duoc thong tin cluster"
        return
    fi

    # Lấy số lượng IP ranges được cấu hình
    local ip_count
    ip_count=$(echo "$AKS_JSON" | \
        jq '.apiServerAccessProfile.authorizedIpRanges // [] | length' 2>/dev/null)

    local ip_ranges
    ip_ranges=$(echo "$AKS_JSON" | \
        jq -r '.apiServerAccessProfile.authorizedIpRanges // [] | join(", ")' 2>/dev/null)

    log_info "authorizedIpRanges ($ip_count entries): $ip_ranges"

    if [ "$ip_count" -eq 0 ] 2>/dev/null; then
        log_fail "5.4.1: authorizedIpRanges = [] → API Server mở public ✗"

        if ask_remediate "Giới hạn API Server chỉ cho IP hiện tại của bạn? [Y/n]: "; then
            local my_ip
            my_ip=$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null)

            if [ -z "$my_ip" ]; then
                log_warn "Không lấy được IP. Sửa thủ công bằng lệnh:"
                log_warn "az aks update --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP --api-server-authorized-ip-ranges <YOUR_IP>/32"
                report_add "5.4.1" "FAIL" "authorizedIpRanges rong - can set thu cong"
            else
                log_info "IP của bạn: $my_ip"
                az aks update \
                    --name "$CLUSTER_NAME" \
                    --resource-group "$RESOURCE_GROUP" \
                    --api-server-authorized-ip-ranges "${my_ip}/32" \
                    --output none 2>/dev/null
                log_info "Đã set authorizedIpRanges = ${my_ip}/32"
                log_warn "Lưu ý: Thêm IP các thành viên khác nếu cần!"
                report_add "5.4.1" "FAIL" "authorizedIpRanges: [] → ${my_ip}/32 (da sua)" "true"
            fi
        else
            report_add "5.4.1" "FAIL" "authorizedIpRanges rong (API Server mo public)"
        fi
    else
        # Có IP nhưng kiểm tra có chứa 0.0.0.0/0 không
        local has_open
        has_open=$(echo "$AKS_JSON" | \
            jq '[.apiServerAccessProfile.authorizedIpRanges // [] | .[] | select(. == "0.0.0.0/0")] | length' 2>/dev/null)

        if [ "$has_open" -gt 0 ] 2>/dev/null; then
            log_fail "5.4.1: authorizedIpRanges chứa 0.0.0.0/0 (mở toàn internet) ✗"
            report_add "5.4.1" "FAIL" "authorizedIpRanges chua 0.0.0.0/0"
        else
            log_pass "5.4.1: authorizedIpRanges = [$ip_ranges] ✓"
            report_add "5.4.1" "PASS" "authorizedIpRanges co $ip_count entry: $ip_ranges"
        fi
    fi
}

# ── MAIN ─────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "${C_BLUE}  CIS AKS Benchmark v1.8.0 - Section 5.1 + 5.4.1      ${C_RESET}"
    echo -e "${C_BLUE}  Azure-level Security Controls                        ${C_RESET}"
    echo -e "${C_BLUE}========================================================${C_RESET}"
    echo -e "  Thời gian: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Kiểm tra công cụ cần thiết
    for tool in az kubectl jq curl; do
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
    check_5_1_1
    check_5_1_2
    check_5_1_3
    check_5_4_1

    report_print_summary
    local report_dir="$SCRIPT_DIR/../../../report"
    report_save_json "$report_dir"
    report_save_html "$report_dir"
}

main
