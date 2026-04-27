#!/bin/bash
# =====================================================================
# common.sh - Các hàm dùng chung cho tất cả CIS AKS Benchmark audit scripts
# CIS AKS Benchmark v1.8.0 - Đồ án NT542
# =====================================================================

# ─────────────────────────────────────────
#  MÀU SẮC TERMINAL
# ─────────────────────────────────────────
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_RESET='\033[0m'

# ─────────────────────────────────────────
#  LOGGER
# ─────────────────────────────────────────
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET}    $1"; }
log_pass() { echo -e "${C_GREEN}[PASS]${C_RESET}    $1"; }
log_fail() { echo -e "${C_RED}[FAIL]${C_RESET}    $1"; }
log_warn() { echo -e "${C_YELLOW}[WARN]${C_RESET}    $1"; }
log_section() { echo -e "\n${C_CYAN}━━━ $1 ━━━${C_RESET}"; }

# ─────────────────────────────────────────
#  CHẠY LỆNH CƠ BẢN
# ─────────────────────────────────────────
run_kubectl() { kubectl "$@"; }
run_az() { az "$@"; }

get_nodes() {
    kubectl get nodes --no-headers -o custom-columns=':metadata.name' | grep -v '^$'
}

# ─────────────────────────────────────────
#  DEBUG POD - Truy cập filesystem của node
# ─────────────────────────────────────────
DEBUG_POD_NAME=""
DEBUG_POD_NS="default"

node_setup() {
    local node_name=$1
    log_info "Tạo debug pod trên node: $node_name ..."

    # Tạo debug pod chạy nền (sleep 3600)
    kubectl debug "node/$node_name" --image=ubuntu:22.04 --quiet -- sh -c "sleep 3600" &>/dev/null &
    
    # Chờ pod xuất hiện (poll tối đa 60s thay vì sleep cố định)
    local deadline=$((SECONDS + 60))
    while [ $SECONDS -lt $deadline ]; do
        DEBUG_POD_NAME=$(kubectl get pods -n default --field-selector spec.nodeName="$node_name" --no-headers -o custom-columns=':metadata.name' 2>/dev/null | grep 'node-debugger' | head -1)
        [ -n "$DEBUG_POD_NAME" ] && break
        sleep 2
    done

    # Chờ pod Ready trước khi exec
    [ -n "$DEBUG_POD_NAME" ] && kubectl wait pod "$DEBUG_POD_NAME" -n default --for=condition=Ready --timeout=30s &>/dev/null

    if [ -z "$DEBUG_POD_NAME" ]; then
        log_warn "Không tạo được debug pod, thử dùng pod kube-system..."
        DEBUG_POD_NAME=$(kubectl get pods -n kube-system --field-selector spec.nodeName="$node_name" --no-headers -o custom-columns=':metadata.name' | grep -E 'azure-cns|kube-proxy' | head -1)
        DEBUG_POD_NS="kube-system"
    else
        DEBUG_POD_NS="default"
    fi

    if [ -n "$DEBUG_POD_NAME" ]; then
        log_info "Sử dụng pod: $DEBUG_POD_NAME (ns: $DEBUG_POD_NS)"
        return 0
    else
        log_warn "Không tìm được pod để truy cập node!"
        return 1
    fi
}

node_exec() {
    local cmd=$1
    if [ -z "$DEBUG_POD_NAME" ]; then
        echo "NO_POD"
        return 1
    fi
    # Thực thi lệnh qua chroot /host
    kubectl exec "$DEBUG_POD_NAME" -n "$DEBUG_POD_NS" -- chroot /host /bin/bash -c "$cmd" 2>/dev/null
}

node_cleanup() {
    if [ -n "$DEBUG_POD_NAME" ] && [ "$DEBUG_POD_NS" == "default" ]; then
        kubectl delete pod "$DEBUG_POD_NAME" -n "$DEBUG_POD_NS" --ignore-not-found=true &>/dev/null
        log_info "Đã dọn dẹp debug pod."
        DEBUG_POD_NAME=""
    fi
}


# ─────────────────────────────────────────
#  KẾT QUẢ AUDIT (Dùng file tạm để lưu state)
# ─────────────────────────────────────────
REPORT_TEMP_FILE=$(mktemp)
REPORT_SECTION=""
REPORT_TITLE=""

# Dọn dẹp file tạm khi script kết thúc
trap 'rm -f "$REPORT_TEMP_FILE"' EXIT

report_init() {
    REPORT_SECTION=$1
    REPORT_TITLE=$2
    > "$REPORT_TEMP_FILE" # Xóa nội dung file cũ
}

report_add() {
    local control_id=$1
    local status=$2
    local detail=$3
    local remediated=${4:-false}
    
    # Lưu dưới dạng TSV (Tab-Separated Values)
    echo -e "${control_id}\t${status}\t${detail}\t${remediated}" >> "$REPORT_TEMP_FILE"
}

report_print_summary() {
    local pass=0 fail=0 warn=0 remediated=0
    
    echo -e "\n${C_BLUE}========================================================${C_RESET}"
    echo -e "${C_BLUE}  KẾT QUẢ - Section ${REPORT_SECTION}: ${REPORT_TITLE}${C_RESET}"
    echo -e "${C_BLUE}========================================================${C_RESET}\n"
    
    printf "  %-10s %-14s %s\n" "Control" "Kết quả" "Chi tiết"
    printf "  %-10s %-14s %s\n" "-------" "-------" "--------"
    
    while IFS=$'\t' read -r id status detail is_remed; do
        if [ "$is_remed" == "true" ]; then status="REMEDIATED"; fi
        
        local color=$C_CYAN
        case "$status" in
            PASS) color=$C_GREEN; ((pass++)) ;;
            FAIL) color=$C_RED; ((fail++)) ;;
            WARN) color=$C_YELLOW; ((warn++)) ;;
            REMEDIATED) color=$C_YELLOW; ((remediated++)) ;;
        esac
        
        local status_colored="${color}${status}${C_RESET}"
        printf "  %-10s %b %s\n" "$id" "$(printf "%-23s" "$status_colored")" "$detail"
    done < "$REPORT_TEMP_FILE"
    
    local rem_str=""
    if [ "$remediated" -gt 0 ]; then
        rem_str=" | ${C_YELLOW}${remediated} REMEDIATED${C_RESET}"
    fi
    echo -e "\n  Tổng kết: PASS:$pass | FAIL:$fail | WARN:$warn${rem_str}"
}

report_save_json() {
    local out_dir=${1:-.}
    mkdir -p "$out_dir"
    local filename="$out_dir/report-${REPORT_SECTION}-$(date +%Y%m%d-%H%M%S).json"
    
    # Sử dụng jq để build JSON an toàn (tránh lỗi escape characters)
    local json_items
    json_items=$(while IFS=$'\t' read -r id status detail is_remed; do
        if [ "$is_remed" == "true" ]; then status="REMEDIATED"; fi
        jq -n --arg c "$id" --arg s "$status" --arg d "$detail" --arg t "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            '{control: $c, status: $s, detail: $d, timestamp: $t}'
    done < "$REPORT_TEMP_FILE" | jq -s '.')
    
    jq -n \
        --arg sec "$REPORT_SECTION" \
        --arg title "$REPORT_TITLE" \
        --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson items "$json_items" \
        '{section: $sec, title: $title, timestamp: $ts, results: $items}' > "$filename"
        
    log_info "📄 JSON report: ${C_CYAN}$filename${C_RESET}"
}

report_save_html() {
    local out_dir=${1:-.}
    mkdir -p "$out_dir"
    local ts=$(date +%Y%m%d-%H%M%S)
    local filename="$out_dir/report-${REPORT_SECTION}-${ts}.html"
    
    local pass=0 fail=0 warn=0 remediated=0
    local rows=""
    
    while IFS=$'\t' read -r id status detail is_remed; do
        if [ "$is_remed" == "true" ]; then status="REMEDIATED"; fi
        local color="#6c757d"
        case "$status" in
            PASS) color="#28a745"; ((pass++)) ;;
            FAIL) color="#dc3545"; ((fail++)) ;;
            WARN) color="#ffc107"; ((warn++)) ;;
            REMEDIATED) color="#fd7e14"; ((remediated++)) ;;
        esac
        
        local safe_detail
        safe_detail=$(printf '%s' "$detail" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        rows+="
            <tr>
                <td><strong>${id}</strong></td>
                <td><span class=\"badge\" style=\"background:${color}\">${status}</span></td>
                <td>${safe_detail}</td>
            </tr>"
    done < "$REPORT_TEMP_FILE"
    
    cat <<EOF > "$filename"
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <title>CIS AKS Benchmark - Section ${REPORT_SECTION}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f8f9fa; }
        .header { background: #1a1a2e; color: white; padding: 24px; border-radius: 8px; margin-bottom: 24px; }
        .header h1 { margin: 0; font-size: 22px; }
        .header p { margin: 4px 0 0; opacity: 0.7; font-size: 14px; }
        .summary { display: flex; gap: 16px; margin-bottom: 24px; }
        .card { flex: 1; padding: 16px; border-radius: 8px; text-align: center; color: white; }
        .card h2 { margin: 0; font-size: 36px; }
        .card p { margin: 4px 0 0; font-size: 13px; opacity: 0.9; }
        table { width: 100%; border-collapse: collapse; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.1); }
        th { background: #343a40; color: white; padding: 12px 16px; text-align: left; }
        td { padding: 12px 16px; border-bottom: 1px solid #dee2e6; }
        tr:hover td { background: #f1f3f5; }
        .badge { padding: 4px 10px; border-radius: 12px; color: white; font-size: 12px; font-weight: bold; }
        .footer { margin-top: 24px; text-align: center; color: #aaa; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>CIS AKS Benchmark v1.8.0 — Section ${REPORT_SECTION}</h1>
        <p>${REPORT_TITLE} &nbsp;|&nbsp; $(date +"%Y-%m-%d %H:%M:%S")</p>
    </div>
    <div class="summary">
        <div class="card" style="background:#28a745"><h2>${pass}</h2><p>PASS</p></div>
        <div class="card" style="background:#dc3545"><h2>${fail}</h2><p>FAIL</p></div>
        <div class="card" style="background:#ffc107"><h2>${warn}</h2><p>WARN</p></div>
        <div class="card" style="background:#fd7e14"><h2>${remediated}</h2><p>REMEDIATED</p></div>
    </div>
    <table>
        <thead><tr><th>Control ID</th><th>Kết quả</th><th>Chi tiết</th></tr></thead>
        <tbody>${rows}</tbody>
    </table>
    <div class="footer">NT542 — CIS AKS Benchmark v1.8.0 — Generated $(date +"%Y-%m-%d %H:%M:%S")</div>
</body>
</html>
EOF

    log_info "🌐 HTML report: ${C_CYAN}$filename${C_RESET}"
}

# ─────────────────────────────────────────
#  AZURE AKS - Thông tin cluster
# ─────────────────────────────────────────
CLUSTER_NAME=""
RESOURCE_GROUP=""
AKS_JSON=""

get_cluster_info() {
    log_info "Lấy thông tin cluster từ Azure..."

    local cluster_list
    cluster_list=$(az aks list --output json 2>/dev/null)

    if [ -z "$cluster_list" ] || [ "$cluster_list" = "[]" ]; then
        log_warn "Không tìm thấy AKS cluster nào! Kiểm tra: az account show"
        return 1
    fi

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

# Lấy toàn bộ thông tin AKS 1 lần, tránh gọi az aks show lặp lại (~2-3 giây/lần)
load_aks_json() {
    if [ -z "$AKS_JSON" ]; then
        log_info "Đang lấy cấu hình cluster từ Azure API..."
        local _result
        _result=$(az aks show \
            --name "$CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --output json 2>/dev/null)
        if [ -z "$_result" ] || [ "$_result" = "null" ]; then
            log_warn "az aks show trả về rỗng — kiểm tra quyền và subscription."
            return 1
        fi
        AKS_JSON="$_result"
    fi
}

# ─────────────────────────────────────────
#  HỎI USER CÓ MUỐN REMEDIATE KHÔNG
# ─────────────────────────────────────────
ask_remediate() {
    local prompt=${1:-"Bạn có muốn tự động sửa không? [Y/n]: "}
    local answer
    
    printf "${C_YELLOW}  → %s${C_RESET}" "$prompt"
    read -r answer
    
    # Chuyển thành chữ thường
    answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]' | xargs)
    
    if [[ "$answer" == "y" || "$answer" == "yes" || -z "$answer" ]]; then
        return 0 # True in Bash
    else
        return 1 # False in Bash
    fi
}