#!/usr/bin/env bash
# =====================================================================
# generate-dashboard.sh - Tạo Dashboard tổng hợp từ các file JSON
# Hỗ trợ giao diện Tab và so sánh Before/After
# =====================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="$PROJECT_ROOT/report"
DASHBOARD_FILE="$REPORT_DIR/dashboard.html"

source "$PROJECT_ROOT/scripts/helpers/common.sh"

log_section "ĐANG TẠO UNIFIED SECURITY DASHBOARD"

if [ ! -d "$REPORT_DIR" ] || [ -z "$(ls -A "$REPORT_DIR"/*.json 2>/dev/null)" ]; then
    log_warn "Không tìm thấy file báo cáo JSON nào trong $REPORT_DIR"
    exit 0
fi

# 1. Phân loại báo cáo V1 (Before) và V2 (After)
V1_REPORTS=$(ls "$REPORT_DIR"/report-*.json 2>/dev/null | grep -v "\-v2\.json$" | sort -r | awk -F'/' '{base=$NF; sub(/^report-/,"",base); sub(/-[0-9]{8}-[0-9]{6}\.json$/,"",base); if (!a[base]++) print $0}')
V2_REPORTS=$(ls "$REPORT_DIR"/report-*-v2.json 2>/dev/null | sort -r | awk -F'/' '{base=$NF; sub(/^report-/,"",base); sub(/-[0-9]{8}-[0-9]{6}-v2\.json$/,"",base); if (!a[base]++) print $0}')

# Hàm tạo table HTML từ danh sách file báo cáo
generate_table_html() {
    local reports=$1
    local rows=""
    local total_pass=0
    local total_fail=0
    local total_warn=0
    local total_remed=0

    for report in $reports; do
        if [ ! -f "$report" ]; then continue; fi
        
        section_data=$(cat "$report")
        
        # Đếm trạng thái
        s_pass=$(echo "$section_data" | jq '.results[] | select(.status=="PASS")' | jq -s 'length')
        s_fail=$(echo "$section_data" | jq '.results[] | select(.status=="FAIL")' | jq -s 'length')
        s_warn=$(echo "$section_data" | jq '.results[] | select(.status=="WARN")' | jq -s 'length')
        s_remed=$(echo "$section_data" | jq '.results[] | select(.status=="REMEDIATED")' | jq -s 'length')
        
        total_pass=$((total_pass + s_pass))
        total_fail=$((total_fail + s_fail))
        total_warn=$((total_warn + s_warn))
        total_remed=$((total_remed + s_remed))

        section_name=$(jq -r '.section' "$report")
        section_title=$(jq -r '.title' "$report")
        
        rows+="<tr class='section-header'><td colspan='3'>Section ${section_name}: ${section_title}</td></tr>"
        
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
            
            rows+="<tr>
                <td style='width: 15%'><strong>${id}</strong></td>
                <td style='width: 15%'><span class='badge bg-${color}'>${status}</span></td>
                <td>${detail}</td>
            </tr>"
        done <<< "$results"
    done

    RET_ROWS="$rows"
    RET_PASS=$total_pass
    RET_FAIL=$total_fail
    RET_WARN=$total_warn
    RET_REMED=$total_remed
    RET_TOTAL=$((total_pass + total_fail + total_warn + total_remed))
}

# Sinh bảng cho Lần 1 (Before)
generate_table_html "$V1_REPORTS"
V1_ROWS="$RET_ROWS"
V1_PASS=$RET_PASS
V1_FAIL=$RET_FAIL
V1_WARN=$RET_WARN
V1_TOTAL=$RET_TOTAL

# Sinh bảng cho Lần 2 (After)
V2_ROWS=""
V2_PASS=0
V2_FAIL=0
V2_WARN=0
if [ -n "$V2_REPORTS" ]; then
    generate_table_html "$V2_REPORTS"
    V2_ROWS="$RET_ROWS"
    V2_PASS=$RET_PASS
    V2_FAIL=$RET_FAIL
    V2_WARN=$RET_WARN
    V2_TOTAL=$RET_TOTAL
fi

PASS_DELTA=$((V2_PASS - V1_PASS))
FAIL_DELTA=$((V1_FAIL - V2_FAIL))
V1_RATE=0
V2_RATE=0
[ "$V1_TOTAL" -gt 0 ] && V1_RATE=$((V1_PASS * 100 / V1_TOTAL))
[ "${V2_TOTAL:-0}" -gt 0 ] && V2_RATE=$((V2_PASS * 100 / V2_TOTAL))

# Nội dung hướng dẫn
TAB_GUIDE="
<h4>Hướng dẫn chạy hệ thống</h4>
<p><strong>1. Khởi chạy toàn bộ Audit (Lần 1):</strong></p>
<pre class='bg-dark text-light p-3 rounded'><code>bash scripts/run-all.sh</code></pre>
<p><strong>2. Thực hiện Remediation tự động:</strong></p>
<pre class='bg-dark text-light p-3 rounded'><code>bash scripts/remediation/remediate-3.x.sh
bash scripts/remediation/remediate-4.x.sh
bash scripts/remediation/remediate-5.x.sh</code></pre>
<p><strong>3. Chạy Audit kiểm chứng lại (Lần 2):</strong></p>
<pre class='bg-dark text-light p-3 rounded'><code>bash scripts/run-audit-v2.sh</code></pre>
"

TAB_VIDEO="
<h4>Kịch bản quay video báo cáo</h4>
<ol>
  <li><strong>Mở đầu:</strong> giới thiệu đồ án NT542, mục tiêu audit AKS theo CIS AKS Benchmark v1.8.0 và cụm <code>aks-cis-audit</code>.</li>
  <li><strong>Tab So sánh:</strong> chỉ vào số liệu BEFORE/AFTER, nhấn mạnh FAIL giảm từ <code>$V1_FAIL</code> xuống <code>$V2_FAIL</code>, PASS tăng từ <code>$V1_PASS</code> lên <code>$V2_PASS</code>.</li>
  <li><strong>Tab Trước Remediation:</strong> trình bày các lỗi chính: Pod Security 4.2.x, NetworkPolicy 4.4.2, Secret env 4.5.1, Namespace boundaries 4.6.1, API IP 5.x.</li>
  <li><strong>Tab Quy trình:</strong> nói rõ 3 lệnh chính: chạy BEFORE, chạy remediation 3.x/4.x/5.x, chạy AFTER.</li>
  <li><strong>Tab Sau Remediation:</strong> chứng minh toàn bộ controls đã PASS, nêu các thay đổi đã áp dụng: harden pod, mount secret dạng file, thêm NetworkPolicy, tạo Namespace boundaries, authorized IP.</li>
  <li><strong>Kết thúc:</strong> kết luận hệ thống đã có dashboard bằng chứng, report JSON/HTML và quy trình có thể chạy lại.</li>
</ol>
<p class='text-muted mb-0'>Gợi ý quay: zoom trình duyệt 90-100%, đi lần lượt các tab từ trái sang phải, dừng 3-5 giây ở mỗi bảng tổng kết.</p>
"

# 3. Ghi file HTML
cat <<'EOF' > "$DASHBOARD_FILE"
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AKS Security Dashboard</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body { background-color: #f4f7f6; font-family: 'Segoe UI', Tahoma, sans-serif; }
        .hero { background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%); color: white; padding: 40px 0; margin-bottom: 30px; }
        .stats-card { border: none; border-radius: 12px; transition: transform 0.2s; box-shadow: 0 4px 6px rgba(0,0,0,0.05); }
        .stats-card:hover { transform: translateY(-5px); }
        .section-header { background-color: #e9ecef; font-weight: bold; color: #495057; }
        .table { background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.05); }
        .badge { font-size: 0.85rem; padding: 0.5em 0.8em; }
        .nav-tabs .nav-link.active { font-weight: bold; color: #1a1a2e; border-bottom: 3px solid #1a1a2e; }
        .nav-tabs .nav-link { color: #6c757d; }
    </style>
</head>
<body>
EOF

cat <<EOF >> "$DASHBOARD_FILE"
<div class="hero">
    <div class="container">
        <h1 class="display-5 fw-bold">AKS Security Dashboard</h1>
        <p class="lead mb-0">CIS Microsoft Azure Kubernetes Service (AKS) Benchmark v1.8.0</p>
        <p class="text-info small mt-2">Quét lần cuối: $(date +"%d/%m/%Y %H:%M:%S")</p>
    </div>
</div>

<div class="container mb-5">
    
    <!-- TABS NAV -->
    <ul class="nav nav-tabs mb-4" id="reportTabs" role="tablist">
        <li class="nav-item" role="presentation">
            <button class="nav-link active" id="before-tab" data-bs-toggle="tab" data-bs-target="#before" type="button" role="tab">Lần 1: Trước Remediation</button>
        </li>
        <li class="nav-item" role="presentation">
            <button class="nav-link" id="after-tab" data-bs-toggle="tab" data-bs-target="#after" type="button" role="tab">Lần 2: Sau Remediation (V2)</button>
        </li>
        <li class="nav-item" role="presentation">
            <button class="nav-link" id="compare-tab" data-bs-toggle="tab" data-bs-target="#compare" type="button" role="tab">So sánh</button>
        </li>
        <li class="nav-item" role="presentation">
            <button class="nav-link" id="guide-tab" data-bs-toggle="tab" data-bs-target="#guide" type="button" role="tab">Quy trình & Lệnh chạy</button>
        </li>
        <li class="nav-item" role="presentation">
            <button class="nav-link" id="video-tab" data-bs-toggle="tab" data-bs-target="#video" type="button" role="tab">Kịch bản video</button>
        </li>
    </ul>

    <!-- TABS CONTENT -->
    <div class="tab-content" id="reportTabsContent">
        
        <!-- LẦN 1: BEFORE -->
        <div class="tab-pane fade show active" id="before" role="tabpanel">
            <div class="row g-4 mb-4">
                <div class="col-md-4">
                    <div class="card stats-card bg-success text-white text-center p-3">
                        <h2>$V1_PASS</h2><p class="mb-0">PASS</p>
                    </div>
                </div>
                <div class="col-md-4">
                    <div class="card stats-card bg-danger text-white text-center p-3">
                        <h2>$V1_FAIL</h2><p class="mb-0">FAIL</p>
                    </div>
                </div>
                <div class="col-md-4">
                    <div class="card stats-card bg-secondary text-white text-center p-3">
                        <h2>$V1_TOTAL</h2><p class="mb-0">TỔNG CỘNG</p>
                    </div>
                </div>
            </div>
            <table class="table table-hover align-middle">
                <thead class="table-dark"><tr><th>Control ID</th><th>Trạng thái</th><th>Chi tiết</th></tr></thead>
                <tbody>$V1_ROWS</tbody>
            </table>
        </div>

        <!-- LẦN 2: AFTER -->
        <div class="tab-pane fade" id="after" role="tabpanel">
EOF

if [ -z "$V2_ROWS" ]; then
cat <<EOF >> "$DASHBOARD_FILE"
            <div class='alert alert-warning mt-3'>Chưa có báo cáo V2. Vui lòng chạy <code>bash scripts/run-audit-v2.sh</code> sau khi hoàn tất sửa lỗi.</div>
EOF
else
cat <<EOF >> "$DASHBOARD_FILE"
            <div class="row g-4 mb-4">
                <div class="col-md-4">
                    <div class="card stats-card bg-success text-white text-center p-3">
                        <h2>$V2_PASS <span class="fs-5 text-light">(Tăng $((V2_PASS - V1_PASS)))</span></h2><p class="mb-0">PASS</p>
                    </div>
                </div>
                <div class="col-md-4">
                    <div class="card stats-card bg-danger text-white text-center p-3">
                        <h2>$V2_FAIL <span class="fs-5 text-light">(Giảm $((V1_FAIL - V2_FAIL)))</span></h2><p class="mb-0">FAIL</p>
                    </div>
                </div>
                <div class="col-md-4">
                    <div class="card stats-card bg-secondary text-white text-center p-3">
                        <h2>$V2_TOTAL</h2><p class="mb-0">TỔNG CỘNG</p>
                    </div>
                </div>
            </div>
            <table class="table table-hover align-middle">
                <thead class="table-dark"><tr><th>Control ID</th><th>Trạng thái</th><th>Chi tiết</th></tr></thead>
                <tbody>$V2_ROWS</tbody>
            </table>
EOF
fi

cat <<EOF >> "$DASHBOARD_FILE"
        </div>

        <!-- SO SÁNH -->
        <div class="tab-pane fade" id="compare" role="tabpanel">
EOF

if [ -z "$V2_ROWS" ]; then
cat <<EOF >> "$DASHBOARD_FILE"
            <div class='alert alert-warning mt-3'>Chưa có dữ liệu AFTER để so sánh.</div>
EOF
else
cat <<EOF >> "$DASHBOARD_FILE"
            <div class="row g-4 mb-4">
                <div class="col-md-3">
                    <div class="card stats-card bg-primary text-white text-center p-3">
                        <h2>$V1_RATE%</h2><p class="mb-0">BEFORE PASS RATE</p>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="card stats-card bg-success text-white text-center p-3">
                        <h2>$V2_RATE%</h2><p class="mb-0">AFTER PASS RATE</p>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="card stats-card bg-success text-white text-center p-3">
                        <h2>+$PASS_DELTA</h2><p class="mb-0">PASS TĂNG</p>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="card stats-card bg-danger text-white text-center p-3">
                        <h2>-$FAIL_DELTA</h2><p class="mb-0">FAIL GIẢM</p>
                    </div>
                </div>
            </div>
            <table class="table table-hover align-middle">
                <thead class="table-dark"><tr><th>Chỉ số</th><th>BEFORE</th><th>AFTER</th><th>Thay đổi</th></tr></thead>
                <tbody>
                    <tr><td><strong>PASS</strong></td><td>$V1_PASS</td><td>$V2_PASS</td><td class="text-success fw-bold">+$PASS_DELTA</td></tr>
                    <tr><td><strong>FAIL</strong></td><td>$V1_FAIL</td><td>$V2_FAIL</td><td class="text-danger fw-bold">-$FAIL_DELTA</td></tr>
                    <tr><td><strong>WARN</strong></td><td>$V1_WARN</td><td>$V2_WARN</td><td>$((V2_WARN - V1_WARN))</td></tr>
                    <tr><td><strong>Tổng controls</strong></td><td>$V1_TOTAL</td><td>$V2_TOTAL</td><td>Không đổi</td></tr>
                </tbody>
            </table>
EOF
fi

cat <<EOF >> "$DASHBOARD_FILE"
        </div>

        <!-- GUIDE -->
        <div class="tab-pane fade" id="guide" role="tabpanel">
            <div class="card p-4 mt-3">
                $TAB_GUIDE
            </div>
        </div>

        <!-- VIDEO SCRIPT -->
        <div class="tab-pane fade" id="video" role="tabpanel">
            <div class="card p-4 mt-3">
                $TAB_VIDEO
            </div>
        </div>

    </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

log_pass "Dashboard đã được tạo thành công với cấu trúc Tab: ${C_CYAN}$DASHBOARD_FILE${C_RESET}"
