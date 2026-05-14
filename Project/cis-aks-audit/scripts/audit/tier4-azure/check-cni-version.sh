#!/bin/bash
# Check CNI (Calico/azure) version and suggest remediation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../helpers/common.sh"

report_init "CNI" "CNI Version Check"

echo ""
echo -e "${C_BLUE}CNI Version Check${C_RESET}"

get_cluster_info || exit 1
load_aks_json || true

local network_plugin
network_plugin=$(echo "$AKS_JSON" | jq -r '.networkProfile.networkPlugin // "none"' 2>/dev/null)
local network_policy
network_policy=$(echo "$AKS_JSON" | jq -r '.networkProfile.networkPolicy // "none"' 2>/dev/null)

log_info "networkPlugin = $network_plugin | networkPolicy = $network_policy"

if [[ "$network_policy" == "calico" || "$network_plugin" == "cilium" || "$network_plugin" == "azure" ]]; then
    # Try detect Calico
    if kubectl get ns calico-system &>/dev/null || kubectl get ns tigera-operator &>/dev/null; then
        log_info "Calico/Tigera detected in cluster - probing images..."
        # Try common DaemonSet names
        local calico_image
        calico_image=$(kubectl -n calico-system get daemonset calico-node -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
        if [ -z "$calico_image" ]; then
            calico_image=$(kubectl -n tigera-operator get deployment tigera-operator -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
        fi

        if [ -n "$calico_image" ]; then
            log_info "Calico image found: $calico_image"
            report_add "CNI.1" "PASS" "Calico image: $calico_image"
            echo ""
            log_warn "Script không tự so sánh với 'latest' — kiểm tra thủ công trên docs.projectcalico.org nếu cần."
            if ask_remediate "Mở guide nâng cấp Calico (tải manifest chính thức) và áp dụng? [Y/n]: "; then
                log_info "Áp dụng Tigera operator manifest (theo hướng dẫn Project Calico)..."
                kubectl apply -f https://docs.projectcalico.org/manifests/tigera-operator.yaml
                log_info "Áp dụng Calico custom resources (nếu cần)..."
                kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
                log_pass "Đã yêu cầu áp dụng manifest Calico (hãy kiểm tra rollout/upgrade kỹ)."
                report_add "CNI.1" "FAIL" "Requested Calico operator/apply (user triggered)" "true"
            fi
        else
            log_warn "Không tìm thấy image Calico qua các DaemonSet/Deployment chuẩn."
            report_add "CNI.2" "WARN" "Không phát hiện Calico images - kiểm tra thủ công"
        fi
    else
        # Not calico - if azure CNI, we can show plugin only
        log_info "No Calico detected; plugin = $network_plugin"
        report_add "CNI.3" "PASS" "CNI plugin = $network_plugin (no version check implemented)"
        log_warn "Không có kiểm tra version tự động cho $network_plugin. Kiểm tra tài liệu nhà cung cấp để biết cách upgrade."
    fi
else
    log_warn "Cluster networkPolicy/plugin không thuộc danh sách kiểm tra (plugin=$network_plugin, policy=$network_policy)"
    report_add "CNI.0" "WARN" "Unsupported CNI/plugin: $network_plugin | policy: $network_policy"
fi

report_print_summary
local report_dir="$SCRIPT_DIR/../../../../report"
report_save_json "$report_dir"
report_save_html "$report_dir"

exit 0
