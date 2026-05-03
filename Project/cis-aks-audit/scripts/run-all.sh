#!/bin/bash
# =====================================================================
# run-all.sh - Master Orchestrator cho CIS AKS Benchmark Audit
# Chạy toàn bộ các tier audit và tập hợp kết quả.
# =====================================================================

# Lấy đường dẫn tuyệt đối của thư mục scripts
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$PROJECT_ROOT/scripts"
REPORT_DIR="$PROJECT_ROOT/report"

# Nạp thư viện dùng chung để lấy màu sắc và hàm log
source "$SCRIPT_DIR/helpers/common.sh"

clear
echo -e "${C_BLUE}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BLUE}║        CIS AKS BENCHMARK V1.8.0 - FULL AUDIT SCAN            ║${C_RESET}"
echo -e "${C_BLUE}║        Hệ thống tự động kiểm tra bảo mật AKS                 ║${C_RESET}"
echo -e "${C_BLUE}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
echo -e "  Bắt đầu quét lúc: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  Thư mục báo cáo: ${C_CYAN}$REPORT_DIR${C_RESET}"

# 1. Kiểm tra môi trường
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

# 2. Danh sách các script cần chạy (theo thứ tự Tier)
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

# 3. Thực thi
TOTAL_SCRIPTS=${#AUDIT_SCRIPTS[@]}
CURRENT=1

for script_path in "${AUDIT_SCRIPTS[@]}"; do
    FULL_PATH="$SCRIPT_DIR/$script_path"
    
    if [ -f "$FULL_PATH" ]; then
        log_section "[$CURRENT/$TOTAL_SCRIPTS] ĐANG CHẠY: $script_path"
        bash "$FULL_PATH"
    else
        log_warn "Không tìm thấy script: $script_path - Bỏ qua."
    fi
    
    ((CURRENT++))
    echo -e "\n--------------------------------------------------------------"
done

# 4. Tạo Dashboard tổng hợp
bash "$SCRIPT_DIR/helpers/generate-dashboard.sh"

# 5. Tổng kết
log_section "HOÀN TẤT QUÁ TRÌNH QUÉT"
echo -e "  Tất cả báo cáo đã được lưu tại: ${C_CYAN}$REPORT_DIR${C_RESET}"
echo -e "  DASHBOARD TỔNG HỢP: ${C_GREEN}$REPORT_DIR/dashboard.html${C_RESET}"
echo -e "  Vui lòng mở Dashboard trong trình duyệt để xem cái nhìn tổng thể."
echo -e "  Kết thúc lúc: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${C_BLUE}══════════════════════════════════════════════════════════════${C_RESET}\n"
