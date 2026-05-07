#!/bin/bash
# =====================================================================
# run-audit-v2.sh - Master Orchestrator cho lần quét số 2 (AFTER)
# Chạy toàn bộ audit sau remediation và lưu report với hậu tố -v2.
# =====================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$PROJECT_ROOT/scripts"
REPORT_DIR="$PROJECT_ROOT/report"

export AUDIT_RUN_VERSION="v2"

source "$SCRIPT_DIR/helpers/common.sh"

clear
echo -e "${C_BLUE}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BLUE}║        CIS AKS BENCHMARK V1.8.0 - AUDIT LẦN 2 (AFTER)       ║${C_RESET}"
echo -e "${C_BLUE}║        Kiểm tra lại sau khi thực hiện remediation            ║${C_RESET}"
echo -e "${C_BLUE}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
echo -e "  Bắt đầu quét lúc: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  Thư mục báo cáo: ${C_CYAN}$REPORT_DIR${C_RESET}"

log_section "KIỂM TRA ĐIỀU KIỆN TIÊN QUYẾT"
for tool in az kubectl jq; do
    if ! command -v "$tool" &>/dev/null; then
        log_fail "Thiếu công cụ: $tool. Vui lòng cài đặt trước."
        exit 1
    fi
    log_pass "Tìm thấy $tool"
done

if ! az account show &>/dev/null; then
    log_fail "Chưa đăng nhập Azure. Vui lòng chạy 'az login' trước."
    exit 1
fi
log_pass "Đã kết nối tài khoản Azure"

AUDIT_SCRIPTS=(
    "audit/tier1-node/audit-3.1.sh"
    "audit/tier2-kubelet/audit-3.2.sh"
    "audit/tier3-k8s/audit-4.1.sh"
    "audit/tier3-pod-security/audit-4.2.sh"
    "audit/tier3-k8s/audit-4.4.sh"
    "audit/tier3-k8s/audit-4.5+4.6.sh"
    "audit/tier4-azure/audit-5.1.sh"
    "audit/tier4-azure/audit-5.4.sh"
)

TOTAL_SCRIPTS=${#AUDIT_SCRIPTS[@]}
CURRENT=1

for script_path in "${AUDIT_SCRIPTS[@]}"; do
    FULL_PATH="$SCRIPT_DIR/$script_path"

    if [ -f "$FULL_PATH" ]; then
        log_section "[$CURRENT/$TOTAL_SCRIPTS] ĐANG CHẠY V2: $script_path"
        bash "$FULL_PATH"
    else
        log_warn "Không tìm thấy script: $script_path - Bỏ qua."
    fi

    ((CURRENT++))
    echo -e "\n--------------------------------------------------------------"
done

bash "$SCRIPT_DIR/helpers/generate-dashboard.sh"

log_section "HOÀN TẤT QUÁ TRÌNH QUÉT LẦN 2"
echo -e "  Tất cả báo cáo V2 đã được lưu tại: ${C_CYAN}$REPORT_DIR${C_RESET}"
echo -e "  DASHBOARD TỔNG HỢP: ${C_GREEN}$REPORT_DIR/dashboard.html${C_RESET}"
echo -e "  Kết thúc lúc: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${C_BLUE}══════════════════════════════════════════════════════════════${C_RESET}\n"
