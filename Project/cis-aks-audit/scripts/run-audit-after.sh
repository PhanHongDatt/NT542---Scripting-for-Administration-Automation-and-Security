#!/bin/bash
# =====================================================================
# run-audit-after.sh - Master Orchestrator cho lần quét số 2 (AFTER)
# Chạy toàn bộ audit sau remediation và so sánh với lần quét trước.
# =====================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$PROJECT_ROOT/scripts"
REPORT_DIR="$PROJECT_ROOT/report"

export AUDIT_RUN_VERSION="v2"

source "$SCRIPT_DIR/helpers/common.sh"

clear
echo -e "${C_BLUE}╔═══════════════════════════════════════════════════════════════╗${C_RESET}"
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

# ── SO SÁNH V1 vs V2 ─────────────────────────────────────────
compare_reports() {
    log_section "SO SÁNH KẾT QUẢ V1 vs V2"

    printf "  %-12s %-10s %-10s %-10s %s\n" "Section" "V1 FAIL" "V2 FAIL" "Thay đổi" "Đánh giá"
    printf "  %-12s %-10s %-10s %-10s %s\n" "-------" "-------" "-------" "--------" "--------"

    local total_v1_fail=0
    local total_v2_fail=0

    for v1_report in "$REPORT_DIR"/report-*-20*.json; do
        # Bỏ qua file v2 và dashboard
        [[ "$v1_report" == *"-v2"* ]] && continue
        [[ "$v1_report" == *"dashboard"* ]] && continue

        local section
        section=$(basename "$v1_report" | sed -E 's/report-([0-9.]+)-.*/\1/')

        local v2_report
        v2_report=$(ls "$REPORT_DIR"/report-"${section}"-*-v2.json 2>/dev/null | tail -1)

        if [ -z "$v2_report" ]; then
            printf "  %-12s %-10s %-10s %-10s %s\n" "$section" "?" "?" "?" "Không có v2"
            continue
        fi

        local v1_fail v2_fail diff
        v1_fail=$(jq '[.results[] | select(.status=="FAIL")] | length' "$v1_report" 2>/dev/null)
        v2_fail=$(jq '[.results[] | select(.status=="FAIL")] | length' "$v2_report" 2>/dev/null)
        v1_fail="${v1_fail:-0}"
        v2_fail="${v2_fail:-0}"
        diff=$((v1_fail - v2_fail))

        total_v1_fail=$((total_v1_fail + v1_fail))
        total_v2_fail=$((total_v2_fail + v2_fail))

        local color eval_text
        if [ "$diff" -gt 0 ]; then
            color=$C_GREEN; eval_text="Cải thiện (-$diff)"
        elif [ "$diff" -lt 0 ]; then
            color=$C_RED; eval_text="Xấu hơn (+$((diff * -1)))"
        elif [ "$v1_fail" -eq 0 ]; then
            color=$C_GREEN; eval_text="Đạt"
        else
            color=$C_YELLOW; eval_text="Không đổi"
        fi

        printf "  %-12s %-10s %-10s %-10s ${color}%s${C_RESET}\n" \
            "$section" "$v1_fail" "$v2_fail" "$diff" "$eval_text"
    done

    echo ""
    local total_diff=$((total_v1_fail - total_v2_fail))
    if [ "$total_diff" -gt 0 ]; then
        echo -e "  ${C_GREEN}Tổng: FAIL giảm từ $total_v1_fail → $total_v2_fail (giảm $total_diff)${C_RESET}"
    elif [ "$total_diff" -lt 0 ]; then
        echo -e "  ${C_RED}Tổng: FAIL tăng từ $total_v1_fail → $total_v2_fail (tăng $((total_diff * -1)))${C_RESET}"
    else
        echo -e "  ${C_YELLOW}Tổng: Không thay đổi ($total_v1_fail FAIL)${C_RESET}"
    fi
}

compare_reports

log_section "HOÀN TẤT QUÁ TRÌNH QUÉT LẦN 2"
echo -e "  Tất cả báo cáo V2 đã được lưu tại: ${C_CYAN}$REPORT_DIR${C_RESET}"
echo -e "  DASHBOARD TỔNG HỢP: ${C_GREEN}$REPORT_DIR/dashboard.html${C_RESET}"
echo -e "  Kết thúc lúc: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${C_BLUE}══════════════════════════════════════════════════════════════${C_RESET}\n"
