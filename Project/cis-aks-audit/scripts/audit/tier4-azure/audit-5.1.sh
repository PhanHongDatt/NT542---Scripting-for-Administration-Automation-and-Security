#!/bin/bash
# ============================================================
#  audit-5.1.sh - CIS AKS Benchmark v1.8.0 - Section 5.1 + 5.4.1
#  Azure-level Security Controls
#
#  Controls:
#    5.1.1 - Microsoft Defender for Containers phải bật
#    5.4.1 - API Server phải giới hạn IP (authorizedIpRanges)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

report_init "5.1+5.4.1" "Azure-level Security Controls"

# ─────────────────────────────────────────
#  Biến cluster (lấy tự động từ Azure CLI)
# ─────────────────────────────────────────
CLUSTER_NAME=""
RESOURCE_GROUP=""
AKS_JSON=""

# ─────────────────────────────────────────
#  HÀM: Lấy tên cluster + resource group
#  từ subscription hiện tại đang đăng nhập
# ─────────────────────────────────────────
get_cluster_info() {
    log_info "Lấy thông tin cluster từ Azure..."

    # az aks list trả về JSON danh sách tất cả cluster trong subscription
    local cluster_list
    cluster_list=$(az aks list --output json 2>/dev/null)

    if [ -z "$cluster_list" ] || [ "$cluster_list" = "[]" ]; then
        log_warn "Không tìm thấy AKS cluster nào! Kiểm tra: az account show"
        return 1
    fi

    # Lấy cluster đầu tiên trong danh sách
    CLUSTER_NAME=$(echo "$cluster_list" | jq -r '.[0].name')
    RESOURCE_GROUP=$(echo "$cluster_list" | jq -r '.[0].resourceGroup')

    if [ -z "$CLUSTER_NAME" ] || [ "$CLUSTER_NAME" = "null" ]; then
        log_warn "Không xác định được tên cluster!"
        return 1
    fi

    log_info "Cluster       : $CLUSTER_NAME"
    log_info "Resource Group: $RESOURCE_GROUP"
    return 0
}

# ─────────────────────────────────────────
#  HÀM: Lấy toàn bộ thông tin AKS 1 lần
#  Tránh gọi az aks show nhiều lần (mỗi lần ~2-3 giây)
# ─────────────────────────────────────────
load_aks_json() {
    if [ -z "$AKS_JSON" ]; then
        log_info "Đang lấy cấu hình cluster từ Azure API..."
        AKS_JSON=$(az aks show \
            --name "$CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --output json 2>/dev/null)
    fi
}

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
            my_ip=$(curl -s https://api.ipify.org 2>/dev/null)

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
    check_5_4_1

    report_print_summary
    local report_dir="$SCRIPT_DIR/../../../report"
    report_save_json "$report_dir"
    report_save_html "$report_dir"
}

main