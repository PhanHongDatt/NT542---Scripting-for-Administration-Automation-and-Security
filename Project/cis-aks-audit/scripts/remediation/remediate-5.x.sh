#!/bin/bash
# =====================================================================
# remediate-5.x.sh
# Remediation cho CIS AKS Benchmark Section 5.x
# Tự động bật Defender, Azure Policy Add-on, và cấu hình IP API Server.
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/common.sh"

main() {
    echo ""
    echo -e "${C_BLUE}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BLUE}║   CIS AKS Benchmark v1.8.0 — Remediation Section 5.x        ║${C_RESET}"
    echo -e "${C_BLUE}║   Azure-level Security Controls                              ║${C_RESET}"
    echo -e "${C_BLUE}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
    echo -e "  Thời gian: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    log_section "ĐANG SỬA LỖI SECTION 5.x (Azure Security Controls)"

    for tool in az jq curl; do
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
    load_aks_json

    # 5.1.1 - Defender
    local pricing_tier
    pricing_tier=$(az security pricing show --name "Containers" --query pricingTier -o tsv 2>/dev/null)
    if [ "$pricing_tier" = "Free" ]; then
        if ask_remediate "5.1.1: Bật Microsoft Defender for Containers (Standard)? [Y/n]: "; then
            log_info "Đang cấu hình Defender..."
            az security pricing create --name "Containers" --tier "Standard" --output none 2>/dev/null \
            && log_pass "Đã bật Microsoft Defender for Containers. ✓" \
            || log_fail "Bật Microsoft Defender for Containers thất bại."
        fi
    else
        log_info "5.1.1: Defender for Containers đã bật ($pricing_tier). ✓"
    fi

    echo ""
    # 5.1.2 - Diagnostic Settings
    local cluster_id
    cluster_id=$(echo "$AKS_JSON" | jq -r '.id // ""')
    local workspace_id
    workspace_id=$(echo "$AKS_JSON" | jq -r '.addonProfiles.omsagent.config.logAnalyticsWorkspaceResourceID // ""')
    local diag_count
    diag_count=$(MSYS_NO_PATHCONV=1 az monitor diagnostic-settings list --resource "$cluster_id" --query "length([?workspaceId != null])" -o tsv 2>/dev/null)
    diag_count="${diag_count:-0}"

    if [ "$diag_count" -eq 0 ] 2>/dev/null; then
        if [ -z "$workspace_id" ] || [ "$workspace_id" = "null" ]; then
            workspace_id=$(az monitor log-analytics workspace show \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "log-aks-audit" \
                --query id -o tsv 2>/dev/null)
        fi

        if [ -z "$workspace_id" ] || [ "$workspace_id" = "null" ]; then
            log_warn "5.1.2: Không xác định được Log Analytics Workspace để tạo Diagnostic Setting."
            log_warn "Lệnh thủ công: az monitor diagnostic-settings create --resource $cluster_id --workspace <WORKSPACE_ID> ..."
        elif ask_remediate "5.1.2: Bật AKS Diagnostic Settings về Log Analytics? [Y/n]: "; then
            log_info "Đang tạo Diagnostic Setting cho AKS control plane..."
            MSYS_NO_PATHCONV=1 az monitor diagnostic-settings create \
                --name "aks-control-plane-logs" \
                --resource "$cluster_id" \
                --workspace "$workspace_id" \
                --logs '[
                    {"category":"kube-apiserver","enabled":true},
                    {"category":"kube-audit","enabled":true},
                    {"category":"kube-audit-admin","enabled":true},
                    {"category":"kube-controller-manager","enabled":true},
                    {"category":"kube-scheduler","enabled":true},
                    {"category":"cluster-autoscaler","enabled":true},
                    {"category":"cloud-controller-manager","enabled":true},
                    {"category":"guard","enabled":true}
                ]' \
                --metrics '[{"category":"AllMetrics","enabled":true}]' \
                --output none 2>/dev/null \
            && log_pass "Đã bật Diagnostic Settings cho AKS. ✓" \
            || log_fail "Tạo Diagnostic Settings thất bại. Kiểm tra quyền Microsoft.Insights/diagnosticSettings/write."
        fi
    else
        log_info "5.1.2: Diagnostic Settings đã trỏ về Log Analytics. ✓"
    fi

    echo ""
    # 5.1.3 - Azure Policy
    local policy_enabled
    policy_enabled=$(echo "$AKS_JSON" | jq -r '.addonProfiles.azurepolicy.enabled // "false"')
    if [ "$policy_enabled" != "true" ]; then
        if ask_remediate "5.1.3: Bật Azure Policy Add-on cho cluster? [Y/n]: "; then
            log_info "Đang bật Azure Policy Add-on (có thể mất vài phút)..."
            az aks enable-addons \
                --addons azure-policy \
                --name "$CLUSTER_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --output none 2>/dev/null \
            && log_pass "Đã bật Azure Policy Add-on. ✓" \
            || log_fail "Bật Azure Policy Add-on thất bại."
        fi
    else
        log_info "5.1.3: Azure Policy Add-on đã bật. ✓"
    fi

    echo ""
    # 5.4.1 - API Server IP
    local ip_count
    ip_count=$(echo "$AKS_JSON" | jq '.apiServerAccessProfile.authorizedIpRanges // [] | length' 2>/dev/null)
    if [ "$ip_count" -eq 0 ] 2>/dev/null; then
        if ask_remediate "5.4.1: Giới hạn API Server chỉ cho IP hiện tại của bạn? [Y/n]: "; then
            local my_ip
            my_ip=$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null)

            if [ -z "$my_ip" ]; then
                log_warn "Không lấy được IP. Sửa thủ công bằng lệnh:"
                log_warn "az aks update --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP --api-server-authorized-ip-ranges <YOUR_IP>/32"
            else
                log_info "IP của bạn: $my_ip"
                log_info "Đang thiết lập IP..."
                az aks update \
                    --name "$CLUSTER_NAME" \
                    --resource-group "$RESOURCE_GROUP" \
                    --api-server-authorized-ip-ranges "${my_ip}/32" \
                    --output none 2>/dev/null \
                && log_pass "Đã set authorizedIpRanges = ${my_ip}/32 ✓" \
                || log_fail "Thiết lập authorizedIpRanges thất bại."
            fi
        fi
    else
        log_info "5.4.1: authorizedIpRanges đã được cấu hình. ✓"
    fi

    echo ""
    log_section "HOÀN TẤT REMEDIATION 5.x"
}

main
