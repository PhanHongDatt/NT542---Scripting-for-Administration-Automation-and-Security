#!/bin/bash
# ============================================================
#  audit-5.1.sh - CIS AKS Benchmark v1.8.0 - Section 5.1 + 5.4.1
#  Azure-level Security Controls
#
#  Controls:
#    5.1.1 - Microsoft Defender for Containers phải bật
#    5.1.2 - Minimize user access to Azure Container Registry (ACR)
#    5.4.1 - API Server phải giới hạn IP (enablePrivateCluster, enablePublicFqdn, authorizedIpRanges)
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
    defender_json=$(az security pricing show --name "ContainerRegistry" --output json 2>/dev/null)

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
        report_add "5.1.1" "FAIL" "Defender pricingTier = Free (tat)"
    else
        log_warn "5.1.1: pricingTier = $pricing_tier (không xác định)"
        report_add "5.1.1" "WARN" "pricingTier = $pricing_tier"
    fi
}

# ─────────────────────────────────────────
#  5.1.2 - Minimize user access to Azure Container Registry (ACR)
#
#  Lý do: Tài khoản Admin của ACR sử dụng mật khẩu dùng chung tĩnh, dễ rò rỉ.
#  Vô hiệu hóa nó để ép buộc xác thực định danh riêng biệt (Entra ID, Managed Identity).
# ─────────────────────────────────────────
check_5_1_2() {
    log_section "5.1.2 - Minimize user access to Azure Container Registry (ACR)"
    log_info "Lý do: Admin Account dùng chung gây mất khả năng kiểm toán lưu vết truy cập theo danh tính cá nhân"

    local acr_list
    acr_list=$(az acr list --query "[].{name:name, resourceGroup:resourceGroup, adminUserEnabled:adminUserEnabled}" --output json 2>/dev/null)

    if [ -z "$acr_list" ] || [ "$acr_list" = "[]" ]; then
        log_warn "5.1.2: Không phát hiện Azure Container Registry (ACR) nào trong Subscription hiện hành."
        report_add "5.1.2" "PASS" "Khong phat hien thuc the ACR nao (Khong ton tai nguy co ranh gioi an ninh tu Admin Account)"
        return
    fi

    local acr_count
    acr_count=$(echo "$acr_list" | jq '. | length' 2>/dev/null)
    log_info "Tìm thấy $acr_count registry trong Subscription."

    local violating_acrs=""
    local fail_count=0

    while read -r acr_info; do
        [ -z "$acr_info" ] && continue
        local name
        name=$(echo "$acr_info" | jq -r '.name')
        local admin_enabled
        admin_enabled=$(echo "$acr_info" | jq -r '.adminUserEnabled')

        if [ "$admin_enabled" = "true" ]; then
            log_fail "  ✗ ACR '$name': Đang bật tài khoản Admin (Admin User = true)"
            violating_acrs="${violating_acrs}${name} "
            ((fail_count++))
        else
            log_pass "  ✓ ACR '$name': Tài khoản Admin đã được vô hiệu hóa (Admin User = false)"
        fi
    done < <(echo "$acr_list" | jq -c '.[]' 2>/dev/null)

    if [ "$fail_count" -eq 0 ]; then
        log_pass "5.1.2: Tất cả ACR đều đã tắt Admin Account ✓"
        report_add "5.1.2" "PASS" "Tat ca cac ACR trong Subscription deu da duoc tat tai khoan Admin"
    else
        violating_acrs=$(echo "$violating_acrs" | xargs)
        log_fail "5.1.2: $fail_count ACR vẫn bật Admin Account: $violating_acrs ✗"
        report_add "5.1.2" "FAIL" "Phat hien $fail_count ACR van dang mo khoa Admin dung chung: $violating_acrs"
    fi
}

# ─────────────────────────────────────────
#  5.4.1 - Restrict Access to the Control Plane Endpoint
#
#  API Server là "cửa vào" của Kubernetes. Nếu để public
#  (authorizedIpRanges rỗng) → attacker có thể tấn công.
#  Kiểm tra theo PDF: enablePrivateCluster, enablePublicFqdn, authorizedIpRanges
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

    # ── Kiểm tra enablePrivateCluster ──
    local private_cluster
    private_cluster=$(echo "$AKS_JSON" | jq -r '.apiServerAccessProfile.enablePrivateCluster // false' 2>/dev/null)
    log_info "enablePrivateCluster = $private_cluster"

    if [ "$private_cluster" = "true" ]; then
        log_pass "5.4.1: enablePrivateCluster = true (Private cluster) ✓"
    else
        log_info "5.4.1: enablePrivateCluster = false (Public cluster — kiểm tra authorizedIpRanges bên dưới)"
    fi

    # ── Kiểm tra enablePublicFqdn ──
    local public_fqdn
    public_fqdn=$(echo "$AKS_JSON" | jq -r '.apiServerAccessProfile.enablePublicFqdn // "not_set"' 2>/dev/null)
    log_info "enablePublicFqdn = $public_fqdn"

    if [ "$public_fqdn" = "true" ]; then
        log_warn "5.4.1: enablePublicFqdn = true — API Server FQDN công khai (nên tắt nếu dùng private cluster)"
    elif [ "$public_fqdn" = "false" ]; then
        log_pass "5.4.1: enablePublicFqdn = false ✓"
    else
        log_info "5.4.1: enablePublicFqdn = không set (mặc định)"
    fi

    # ── Kiểm tra authorizedIpRanges ──
    local ip_count
    ip_count=$(echo "$AKS_JSON" | \
        jq '.apiServerAccessProfile.authorizedIpRanges // [] | length' 2>/dev/null)

    local ip_ranges
    ip_ranges=$(echo "$AKS_JSON" | \
        jq -r '.apiServerAccessProfile.authorizedIpRanges // [] | join(", ")' 2>/dev/null)

    log_info "authorizedIpRanges ($ip_count entries): $ip_ranges"

    if [ "$ip_count" -eq 0 ] 2>/dev/null; then
        if [ "$private_cluster" = "true" ]; then
            log_pass "5.4.1: Private cluster + authorizedIpRanges rỗng (OK — private endpoint) ✓"
            report_add "5.4.1" "PASS" "Private cluster, enablePublicFqdn=$public_fqdn"
        else
            log_fail "5.4.1: authorizedIpRanges = [] → API Server mở public ✗"
            report_add "5.4.1" "FAIL" "authorizedIpRanges rong (API Server mo public)"
        fi
    else
        local has_open
        has_open=$(echo "$AKS_JSON" | \
            jq '[.apiServerAccessProfile.authorizedIpRanges // [] | .[] | select(. == "0.0.0.0/0")] | length' 2>/dev/null)

        if [ "$has_open" -gt 0 ] 2>/dev/null; then
            log_fail "5.4.1: authorizedIpRanges chứa 0.0.0.0/0 (mở toàn internet) ✗"
            report_add "5.4.1" "FAIL" "authorizedIpRanges chua 0.0.0.0/0"
        else
            log_pass "5.4.1: authorizedIpRanges = [$ip_ranges] ✓"
            report_add "5.4.1" "PASS" "privateCluster=$private_cluster, publicFqdn=$public_fqdn, IPs=$ip_count"
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
    check_5_4_1

    report_print_summary
    local report_dir="$SCRIPT_DIR/../../../report"
    report_save_json "$report_dir"
    report_save_html "$report_dir"
}

main
