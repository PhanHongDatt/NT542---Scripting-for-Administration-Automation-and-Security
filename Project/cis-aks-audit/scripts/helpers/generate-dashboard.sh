#!/bin/bash
# =====================================================================
# generate-dashboard.sh - Tạo Dashboard tổng hợp từ các file JSON
# =====================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="$PROJECT_ROOT/report"
DASHBOARD_FILE="$REPORT_DIR/dashboard.html"

# Nạp màu sắc
source "$PROJECT_ROOT/scripts/helpers/common.sh"

log_section "ĐANG TẠO UNIFIED SECURITY DASHBOARD"

if [ ! -d "$REPORT_DIR" ] || [ -z "$(ls -A "$REPORT_DIR"/*.json 2>/dev/null)" ]; then
    log_warn "Không tìm thấy file báo cáo JSON nào trong $REPORT_DIR"
    exit 0
fi

# 1. Thu thập dữ liệu tổng quát
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_WARN=0
TOTAL_REMEDIATED=0
SECTIONS_JSON=""

# Lấy danh sách các file JSON mới nhất của mỗi section (để tránh lặp nếu chạy nhiều lần)
# Ta sẽ lấy các file có timestamp mới nhất trong tên file
LATEST_REPORTS=$(ls "$REPORT_DIR"/report-*.json | sort -r | awk -F'report-|-' '{if (!a[$2]++) print $0}')

for report in $LATEST_REPORTS; do
    section_data=$(cat "$report")
    s_pass=$(echo "$section_data" | jq '.results[] | select(.status=="PASS")' | jq -s 'length')
    s_fail=$(echo "$section_data" | jq '.results[] | select(.status=="FAIL")' | jq -s 'length')
    s_warn=$(echo "$section_data" | jq '.results[] | select(.status=="WARN")' | jq -s 'length')
    s_remed=$(echo "$section_data" | jq '.results[] | select(.status=="REMEDIATED")' | jq -s 'length')
    
    TOTAL_PASS=$((TOTAL_PASS + s_pass))
    TOTAL_FAIL=$((TOTAL_FAIL + s_fail))
    TOTAL_WARN=$((TOTAL_WARN + s_warn))
    TOTAL_REMEDIATED=$((TOTAL_REMEDIATED + s_remed))
done

TOTAL_CONTROLS=$((TOTAL_PASS + TOTAL_FAIL + TOTAL_WARN + TOTAL_REMEDIATED))

# 2. Tạo nội dung bảng
ROWS=""
for report in $LATEST_REPORTS; do
    section_name=$(jq -r '.section' "$report")
    section_title=$(jq -r '.title' "$report")
    
    ROWS+="<tr class='section-header'><td colspan='3'>Section ${section_name}: ${section_title}</td></tr>"
    
    results=$(jq -c '.results[]' "$report")
    while IFS= read -r res; do
        id=$(echo "$res" | jq -r '.control')
        status=$(echo "$res" | jq -r '.status')
        detail=$(echo "$res" | jq -r '.detail' | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        
        color="secondary"
        case "$status" in
            PASS) color="success" ;;
            FAIL) color="danger" ;;
            WARN) color="warning text-dark" ;;
            REMEDIATED) color="info" ;;
        esac
        
        ROWS+="<tr>
            <td style='width: 15%'><strong>$id</strong></td>
            <td style='width: 15%'><span class='badge bg-$color'>$status</span></td>
            <td>$detail</td>
        </tr>"
    done <<< "$results"
done

# 3. Ghi file HTML
cat <<EOF > "$DASHBOARD_FILE"
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AKS Security Dashboard - CIS Benchmark</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { background-color: #f4f7f6; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; }
        .hero { background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%); color: white; padding: 40px 0; margin-bottom: 30px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); }
        .stats-card { border: none; border-radius: 12px; transition: transform 0.2s; box-shadow: 0 4px 6px rgba(0,0,0,0.05); }
        .stats-card:hover { transform: translateY(-5px); }
        .section-header { background-color: #e9ecef; font-weight: bold; color: #495057; }
        .table { background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.05); }
        .badge { font-size: 0.85rem; padding: 0.5em 0.8em; }
        .footer { margin-top: 50px; padding: 20px; color: #6c757d; font-size: 0.9rem; border-top: 1px solid #dee2e6; }
    </style>
</head>
<body>

<div class="hero">
    <div class="container">
        <div class="row align-items-center">
            <div class="col-md-8">
                <h1 class="display-5 fw-bold">AKS Security Dashboard</h1>
                <p class="lead mb-0">CIS Microsoft Azure Kubernetes Service (AKS) Benchmark v1.8.0</p>
                <p class="text-info small">Quét lần cuối: $(date +"%d/%m/%Y %H:%M:%S")</p>
            </div>
            <div class="col-md-4 text-end">
                <div class="h2 mb-0 fw-bold">$TOTAL_CONTROLS</div>
                <div class="small text-uppercase opacity-75">Tổng số Controls</div>
            </div>
        </div>
    </div>
</div>

<div class="container">
    <div class="row g-4 mb-5">
        <div class="col-md-3">
            <div class="card stats-card bg-success text-white h-100">
                <div class="card-body text-center">
                    <h2 class="display-4 fw-bold">$TOTAL_PASS</h2>
                    <p class="mb-0 text-uppercase">Tốt (PASS)</p>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card stats-card bg-danger text-white h-100">
                <div class="card-body text-center">
                    <h2 class="display-4 fw-bold">$TOTAL_FAIL</h2>
                    <p class="mb-0 text-uppercase">Nguy cơ (FAIL)</p>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card stats-card bg-warning text-dark h-100">
                <div class="card-body text-center">
                    <h2 class="display-4 fw-bold">$TOTAL_WARN</h2>
                    <p class="mb-0 text-uppercase">Cảnh báo (WARN)</p>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card stats-card bg-info text-white h-100">
                <div class="card-body text-center">
                    <h2 class="display-4 fw-bold">$TOTAL_REMEDIATED</h2>
                    <p class="mb-0 text-uppercase">Đã sửa (REMED)</p>
                </div>
            </div>
        </div>
    </div>

    <div class="row">
        <div class="col-12">
            <div class="table-responsive">
                <table class="table table-hover align-middle">
                    <thead class="table-dark">
                        <tr>
                            <th>Control ID</th>
                            <th>Trạng thái</th>
                            <th>Chi tiết kết quả</th>
                        </tr>
                    </thead>
                    <tbody>
                        $ROWS
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <div class="footer text-center">
        Dự án đồ án NT542 - Lập trình kịch bản & Bảo mật - UIT <br>
        Báo cáo tự động hóa dựa trên CIS Benchmark v1.8.0
    </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

log_pass "Dashboard đã được tạo thành công: ${C_CYAN}$DASHBOARD_FILE${C_RESET}"
