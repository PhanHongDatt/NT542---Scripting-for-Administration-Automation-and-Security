#!/bin/bash
# =====================================================================
# audit-3.2.sh - CIS AKS Benchmark v1.8.0 - Section 3.2
# Worker Node Configuration - Kubelet
# =====================================================================

# Lấy đường dẫn tuyệt đối của thư mục chứa script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/common.sh"

# Khởi tạo báo cáo cho Section 3.2
report_init "3.2" "Worker Node Kubelet Configuration"

# ─────────────────────────────────────────
#  HEADER & THÔNG TIN CHUNG
# ─────────────────────────────────────────
echo -e "\n${C_BLUE}========================================================${C_RESET}"
echo -e "${C_BLUE}   CIS AKS Benchmark v1.8.0 - Section 3.2${C_RESET}"
echo -e "${C_BLUE}   Worker Node Configuration - Kubelet${C_RESET}"
echo -e "${C_BLUE}========================================================${C_RESET}"
echo -e "   Thời gian: $(date '+%Y-%m-%d %H:%M:%S')\n"

# 1. Lấy danh sách nodes trong cluster
NODES=$(get_nodes)
if [ -z "$NODES" ]; then
    log_warn "Không tìm thấy node nào! Kiểm tra: kubectl get nodes"
    exit 1
fi

log_info "Tìm thấy $(echo "$NODES" | wc -l) node(s): $(echo "$NODES" | xargs | sed 's/ /, /g')"

# 2. Hàm hỗ trợ lấy giá trị của 1 flag từ kubelet process args (Thay thế get_arg trong Python)
# AKS truyền tất cả qua process args: --anonymous-auth=false...
extract_arg() {
    local args="$1"
    local flag="$2"
    # Dùng regex lấy giá trị sau dấu = cho đến khi gặp khoảng trắng
    local val=$(echo "$args" | grep -oP "(?<=${flag}=)[^ ]+" | tr -d "'\"")
    if [ -z "$val" ]; then
        echo "NOT_SET"
    else
        echo "$val"
    fi
}

# 3. Lặp qua từng node để kiểm tra
for NODE_NAME in $NODES; do
    echo -e "\n${C_BLUE}╔══════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BLUE}║  NODE: $NODE_NAME${C_RESET}"
    echo -e "${C_BLUE}╚══════════════════════════════════════════╝${C_RESET}"

    # Tạo debug pod để truy cập node
    node_setup "$NODE_NAME"
    if [ $? -ne 0 ]; then
        log_warn "Bỏ qua node $NODE_NAME - không truy cập được."
        continue
    fi

    # Lấy kubelet process arguments (Tương đương get_kubelet_args trong Python)
    KUBELET_ARGS=$(node_exec "ps -ef | grep -E '/opt/bin/kubelet|/usr/bin/kubelet' | grep -v grep | head -1")
    
    if [ -z "$KUBELET_ARGS" ] || [[ "$KUBELET_ARGS" == "ERROR" ]]; then
        log_warn "Không lấy được kubelet args trên node $NODE_NAME!"
        node_cleanup
        continue
    fi

    log_info "Đã lấy kubelet process args thành công."

    # --- 3.2.1: --anonymous-auth = false ---
    log_section "3.2.1 - Ensure --anonymous-auth = false"
    log_info "Lý do: anonymous-auth=true cho phép bất kỳ ai gọi Kubelet API không cần xác thực"
    VAL=$(extract_arg "$KUBELET_ARGS" "--anonymous-auth")
    log_info "--anonymous-auth = $VAL"
    if [ "$VAL" == "false" ]; then
        log_pass "3.2.1: --anonymous-auth = false"
        report_add "3.2.1" "PASS" "--anonymous-auth = false"
    elif [ "$VAL" == "NOT_SET" ]; then
        log_fail "3.2.1: --anonymous-auth không set → mặc định true"
        report_add "3.2.1" "FAIL" "--anonymous-auth không set (mặc định true)"
    else
        log_fail "3.2.1: --anonymous-auth = $VAL"
        report_add "3.2.1" "FAIL" "--anonymous-auth = $VAL"
    fi

    # --- 3.2.2: --authorization-mode != AlwaysAllow ---
    log_section "3.2.2 - Ensure --authorization-mode != AlwaysAllow"
    log_info "Lý do: AlwaysAllow bypass toàn bộ authorization"
    VAL=$(extract_arg "$KUBELET_ARGS" "--authorization-mode")
    log_info "--authorization-mode = $VAL"
    if [ "$VAL" == "AlwaysAllow" ]; then
        log_fail "3.2.2: --authorization-mode = AlwaysAllow (rất nguy hiểm!)"
        report_add "3.2.2" "FAIL" "--authorization-mode = AlwaysAllow"
    elif [ "$VAL" == "NOT_SET" ]; then
        log_warn "3.2.2: --authorization-mode không set → cần kiểm tra thủ công"
        report_add "3.2.2" "WARN" "--authorization-mode không set"
    else
        log_pass "3.2.2: --authorization-mode = $VAL"
        report_add "3.2.2" "PASS" "--authorization-mode = $VAL"
    fi

    # --- 3.2.3: --client-ca-file set và tồn tại ---
    log_section "3.2.3 - Ensure --client-ca-file được set"
    log_info "Lý do: CA file cho phép kubelet xác minh certificate của API server"
    VAL=$(extract_arg "$KUBELET_ARGS" "--client-ca-file")
    log_info "--client-ca-file = $VAL"
    if [ "$VAL" == "NOT_SET" ]; then
        log_fail "3.2.3: --client-ca-file chưa được set"
        report_add "3.2.3" "FAIL" "--client-ca-file = NOT_SET"
    else
        EXISTS=$(node_exec "[ -f '$VAL' ] && echo yes || echo no")
        if [ "$EXISTS" == "yes" ]; then
            log_pass "3.2.3: --client-ca-file = $VAL (file tồn tại)"
            report_add "3.2.3" "PASS" "--client-ca-file = $VAL"
        else
            log_fail "3.2.3: --client-ca-file = $VAL nhưng FILE KHÔNG TỒN TẠI"
            report_add "3.2.3" "FAIL" "File không tồn tại: $VAL"
        fi
    fi

    # --- 3.2.4: --read-only-port = 0 ---
    log_section "3.2.4 - Ensure --read-only-port = 0"
    log_info "Lý do: Port 10255 expose thông tin pods/nodes không cần xác thực"
    VAL=$(extract_arg "$KUBELET_ARGS" "--read-only-port")
    log_info "--read-only-port = $VAL"
    if [ "$VAL" == "0" ]; then
        log_pass "3.2.4: --read-only-port = 0 (disabled)"
        report_add "3.2.4" "PASS" "--read-only-port = 0"
    elif [ "$VAL" == "NOT_SET" ]; then
        log_warn "3.2.4: --read-only-port không set → có thể mặc định 10255"
        report_add "3.2.4" "WARN" "--read-only-port không set"
    else
        log_fail "3.2.4: --read-only-port = $VAL (cần = 0)"
        report_add "3.2.4" "FAIL" "--read-only-port = $VAL"
    fi

    # --- 3.2.5: --streaming-connection-idle-timeout != 0 ---
    log_section "3.2.5 - Ensure --streaming-connection-idle-timeout != 0"
    log_info "Lý do: Timeout=0 giữ connections mở vĩnh viễn"
    VAL=$(extract_arg "$KUBELET_ARGS" "--streaming-connection-idle-timeout")
    log_info "--streaming-connection-idle-timeout = $VAL"
    if [[ "$VAL" == "0" || "$VAL" == "0s" ]]; then
        log_fail "3.2.5: --streaming-connection-idle-timeout = 0"
        report_add "3.2.5" "FAIL" "--streaming-connection-idle-timeout = 0"
    elif [ "$VAL" == "NOT_SET" ]; then
        log_pass "3.2.5: Không set → mặc định 4h (khác 0)"
        report_add "3.2.5" "PASS" "--streaming-connection-idle-timeout = 4h (mặc định)"
    else
        log_pass "3.2.5: --streaming-connection-idle-timeout = $VAL"
        report_add "3.2.5" "PASS" "--streaming-connection-idle-timeout = $VAL"
    fi

    # --- 3.2.6: --make-iptables-util-chains = true ---
    log_section "3.2.6 - Ensure --make-iptables-util-chains = true"
    log_info "Lý do: Kubelet cần quản lý iptables để đảm bảo network routing đúng"
    VAL=$(extract_arg "$KUBELET_ARGS" "--make-iptables-util-chains")
    log_info "--make-iptables-util-chains = $VAL"
    if [ "$VAL" == "false" ]; then
        log_fail "3.2.6: --make-iptables-util-chains = false"
        report_add "3.2.6" "FAIL" "--make-iptables-util-chains = false"
    else
        DISPLAY_VAL=$VAL; [ "$VAL" == "NOT_SET" ] && DISPLAY_VAL="true (mặc định)"
        log_pass "3.2.6: --make-iptables-util-chains = $DISPLAY_VAL"
        report_add "3.2.6" "PASS" "--make-iptables-util-chains = $DISPLAY_VAL"
    fi

    # --- 3.2.7: --event-qps >= 0 [Level 2] ---
    log_section "3.2.7 - Ensure --event-qps >= 0 [Level 2]"
    log_info "Lý do: Rate quá thấp có thể bỏ sót security events"
    VAL=$(extract_arg "$KUBELET_ARGS" "--event-qps")
    log_info "--event-qps = $VAL"
    if [ "$VAL" == "NOT_SET" ]; then
        log_pass "3.2.7: --event-qps không set → mặc định 50"
        report_add "3.2.7" "PASS" "--event-qps = 50 (mặc định)"
    elif [[ "$VAL" =~ ^-?[0-9]+$ ]] && [ "$VAL" -ge 0 ]; then
        log_pass "3.2.7: --event-qps = $VAL (>= 0)"
        report_add "3.2.7" "PASS" "--event-qps = $VAL"
    else
        log_fail "3.2.7: --event-qps = $VAL"
        report_add "3.2.7" "FAIL" "--event-qps = $VAL"
    fi

    # --- 3.2.8: --rotate-certificates != false [Level 2] ---
    log_section "3.2.8 - Ensure --rotate-certificates != false [Level 2]"
    log_info "Lý do: Certificate rotation đảm bảo kubelet luôn có cert hợp lệ"
    VAL=$(extract_arg "$KUBELET_ARGS" "--rotate-certificates")
    log_info "--rotate-certificates = $VAL"
    if [ "$VAL" == "false" ]; then
        log_fail "3.2.8: --rotate-certificates = false"
        report_add "3.2.8" "FAIL" "--rotate-certificates = false"
    else
        DISPLAY_VAL=$VAL; [ "$VAL" == "NOT_SET" ] && DISPLAY_VAL="true (mặc định)"
        log_pass "3.2.8: --rotate-certificates = $DISPLAY_VAL"
        report_add "3.2.8" "PASS" "--rotate-certificates = $DISPLAY_VAL"
    fi

    # --- 3.2.9: RotateKubeletServerCertificate = true ---
    log_section "3.2.9 - Ensure RotateKubeletServerCertificate = true"
    log_info "Lý do: Server cert rotation tự động thay cert hết hạn"
    FG_VAL=$(extract_arg "$KUBELET_ARGS" "--feature-gates")
    log_info "--feature-gates = $FG_VAL"
    
    ROT_VAL="NOT_SET"
    if [ "$FG_VAL" != "NOT_SET" ]; then
        # Tìm riêng RotateKubeletServerCertificate trong chuỗi feature-gates
        ROT_VAL=$(echo "$FG_VAL" | grep -oP "RotateKubeletServerCertificate=\K\w+")
    fi
    log_info "RotateKubeletServerCertificate = $ROT_VAL"

    if [ "$ROT_VAL" == "true" ]; then
        log_pass "3.2.9: RotateKubeletServerCertificate = true"
        report_add "3.2.9" "PASS" "RotateKubeletServerCertificate = true (feature-gates)"
    elif [ "$ROT_VAL" == "false" ]; then
        log_fail "3.2.9: RotateKubeletServerCertificate = false"
        report_add "3.2.9" "FAIL" "RotateKubeletServerCertificate = false"
    else
        log_pass "3.2.9: Không set tường minh → mặc định true (K8s >= 1.12)"
        report_add "3.2.9" "PASS" "RotateKubeletServerCertificate = true (mặc định)"
    fi

    # Xóa debug pod sau khi xong
    node_cleanup
done

# 4. In và lưu báo cáo
report_print_summary
REPORT_DIR="$SCRIPT_DIR/../../../report"
report_save_json "$REPORT_DIR"
report_save_html "$REPORT_DIR"