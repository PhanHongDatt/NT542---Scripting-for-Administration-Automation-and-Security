#!/bin/bash
# =====================================================================
# run-remediate.sh - Master Orchestrator cho Remediation
# Chạy tất cả remediation scripts theo thứ tự.
# =====================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$PROJECT_ROOT/scripts"

source "$SCRIPT_DIR/helpers/common.sh"

clear
echo -e "${C_BLUE}╔═══════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BLUE}║        CIS AKS BENCHMARK V1.8.0 - REMEDIATION                ║${C_RESET}"
echo -e "${C_BLUE}║        Tự động khắc phục các tiêu chí FAIL                   ║${C_RESET}"
echo -e "${C_BLUE}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
echo -e "  Thời gian: $(date '+%Y-%m-%d %H:%M:%S')"

REMEDIATION_SCRIPTS=(
    "remediation/remediate-3.x.sh"
    "remediation/remediate-4.x.sh"
    "remediation/remediate-5.x.sh"
)

TOTAL=${#REMEDIATION_SCRIPTS[@]}
CURRENT=1

for script_path in "${REMEDIATION_SCRIPTS[@]}"; do
    FULL_PATH="$SCRIPT_DIR/$script_path"

    if [ -f "$FULL_PATH" ]; then
        log_section "[$CURRENT/$TOTAL] ĐANG CHẠY: $script_path"
        bash "$FULL_PATH"
    else
        log_warn "Không tìm thấy script: $script_path - Bỏ qua."
    fi

    ((CURRENT++))
    echo -e "\n--------------------------------------------------------------"
done

log_section "HOÀN TẤT REMEDIATION"
echo -e "  Chạy audit lại để xác minh: ${C_CYAN}bash scripts/run-audit-after.sh${C_RESET}"
echo -e "  Thời gian: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${C_BLUE}══════════════════════════════════════════════════════════════${C_RESET}\n"
