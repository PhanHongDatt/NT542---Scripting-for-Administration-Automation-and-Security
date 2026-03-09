#!/bin/bash
# ============================================================
# manage_web.sh - Quản lý website OpenCart trên Ubuntu 22.04
# Nhóm: 08 | Môn: NT542
# TV1 - Quyền   : deploy_site()
# TV2 - Đạt     : analyze_site()
# TV3 - Kiên    : backup_site()
# TV4 - Đăng    : main() + tích hợp
# ============================================================

# --- BIẾN CHUNG (tất cả thành viên dùng các biến này) ---
WEB_ROOT="/var/www/opencart"
DB_NAME="opencart_db"
DB_USER="opencart_user"
DB_PASS="StrongPass@2024"
DB_ROOT_PASS="RootPass@2024"
BACKUP_DIR="/var/backups/opencart"
LOG_FILE="/var/log/manage_web.log"
LAST_BACKUP_FILE="/var/backups/opencart/.last_backup"
OPENCART_VERSION="4.0.2.3"
OPENCART_URL="https://github.com/opencart/opencart/releases/download/${OPENCART_VERSION}/opencart-${OPENCART_VERSION}.zip"
S3_BUCKET_NAME="opencart-backup-23520231"

# --- SET COLOR CHO OUTPUT ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# PHẦN TV4: HÀM TIỆN ÍCH, LOGGING, KIỂM TRA ĐIỀU KIỆN
# ============================================================

log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
info()    { echo -e "${BLUE}[INFO]${NC} $1";    log "[INFO] $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1";     log "[OK] $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1";  log "[WARN] $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1";    log "[ERROR] $1"; exit 1; }

check_root() {
    [[ $EUID -ne 0 ]] && error "Script phải chạy với quyền root (sudo)"
}

check_disk_space() {
    local required_gb=$1
    local available
    available=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    [[ $available -lt $required_gb ]] && \
        error "Không đủ dung lượng. Cần ${required_gb}GB, còn ${available}GB"
    success "Kiểm tra dung lượng: OK (${available}GB khả dụng)"
}

# ============================================================
# PHẦN TV1: MODULE TRIỂN KHAI OPENCART
# ============================================================

deploy_site() {
    info "=== BẮT ĐẦU TRIỂN KHAI OPENCART ==="
    check_disk_space 3

    # 1. Cập nhật hệ thống
    info "Cập nhật danh sách gói..."
    apt-get update -qq || error "Lỗi apt-get update"

    # 2. Cài đặt Apache
    info "Cài đặt Apache2..."
    apt-get install -y apache2 || error "Lỗi cài Apache2"
    systemctl enable apache2 && systemctl start apache2

    # (Fixed) 3. Cài đặt MariaDB
    info "Cài đặt MariaDB..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server || \
        error "Lỗi cài MariaDB"
    systemctl enable mariadb && systemctl start mariadb

    # Đặt mật khẩu root MariaDB (Bỏ qua lỗi nếu root đã có mật khẩu)
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';" 2>/dev/null || \
    mysql -u root -p"${DB_ROOT_PASS}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';" 2>/dev/null
    mysql -u root -p"${DB_ROOT_PASS}" -e "FLUSH PRIVILEGES;"

    # 4. Cài đặt hệ sinh thái PHP (Tự động theo OS, vd 8.1 trên 22.04 và 8.3 trên 24.04)
    info "Cài đặt PHP và các extensions..."
    apt-get install -y php libapache2-mod-php \
        php-mysql php-curl php-gd php-intl \
        php-mbstring php-xml php-zip php-bcmath \
        unzip wget || error "Lỗi cài PHP extensions"

    # 5. Tạo Database và User
    info "Tạo Database và User cho OpenCart..."
    mysql -u root -p"${DB_ROOT_PASS}" <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    success "Database '${DB_NAME}' và user '${DB_USER}' đã được tạo"

    # 6. Tải và giải nén OpenCart
    info "Tải OpenCart ${OPENCART_VERSION}..."
    TMP_DIR=$(mktemp -d)
    wget -q "${OPENCART_URL}" -O "${TMP_DIR}/opencart.zip" || \
        error "Lỗi tải OpenCart"
    unzip -q "${TMP_DIR}/opencart.zip" -d "${TMP_DIR}"

    # Tự động tìm thư mục upload
    UPLOAD_PATH=$(find "${TMP_DIR}" -type d -name "upload" | head -n 1)
    if [ -z "$UPLOAD_PATH" ]; then
        error "Không tìm thấy thư mục 'upload' trong file giải nén!"
    fi

    mkdir -p "${WEB_ROOT}"
    cp -r "${UPLOAD_PATH}/." "${WEB_ROOT}/"
    rm -rf "${TMP_DIR}"

    # Tạo file config từ mẫu
    cp "${WEB_ROOT}/config-dist.php"       "${WEB_ROOT}/config.php"
    cp "${WEB_ROOT}/admin/config-dist.php" "${WEB_ROOT}/admin/config.php"

    # 7. Phân quyền
    info "Phân quyền thư mục..."
    chown -R www-data:www-data "${WEB_ROOT}"
    find "${WEB_ROOT}" -type d -exec chmod 755 {} \;
    find "${WEB_ROOT}" -type f -exec chmod 644 {} \;
    chmod -R 777 "${WEB_ROOT}/system/storage"
    chmod -R 777 "${WEB_ROOT}/image"

    # 8. Cấu hình Apache VirtualHost
    info "Cấu hình Apache VirtualHost..."
    cat > /etc/apache2/sites-available/opencart.conf <<APACHE
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot ${WEB_ROOT}
    <Directory ${WEB_ROOT}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/opencart_error.log
    CustomLog \${APACHE_LOG_DIR}/opencart_access.log combined
</VirtualHost>
APACHE

    a2ensite opencart.conf
    a2enmod rewrite
    a2dissite 000-default.conf 2>/dev/null
    systemctl restart apache2

    success "=== TRIỂN KHAI HOÀN TẤT ==="
    info "Truy cập: http://localhost để cài đặt OpenCart"
    info "DB: ${DB_NAME} | User: ${DB_USER} | Pass: ${DB_PASS}"
}

# ============================================================
# PHẦN TV2: MODULE PHÂN TÍCH HỆ THỐNG
# ============================================================

analyze_site() {
    info "=== BẮT ĐẦU PHÂN TÍCH HỆ THỐNG ==="

    if [[ ! -d "$WEB_ROOT" ]]; then
        error "Thư mục ${WEB_ROOT} không tồn tại. Hãy chạy Deploy trước!"
    fi

    REPORT_FILE="${BACKUP_DIR}/analyze_report_$(date +%F).txt"
    mkdir -p "$BACKUP_DIR"

    info "Đang quét ${WEB_ROOT}... (có thể mất vài giây)"

    # Dùng cấu trúc { } để capture tất cả output vào cả màn hình và file
    {
        echo "================================================================"
        echo "  BÁO CÁO PHÂN TÍCH HỆ THỐNG"
        echo "  Thời gian : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  Website   : $WEB_ROOT"
        echo "  Thực hiện : $(whoami)@$(hostname)"
        echo "================================================================"
        echo ""

        # --- 1. Tổng quan ---
        echo "--- [1] TỔNG QUAN ---"
        TOTAL_FILES=$(find "$WEB_ROOT" -type f 2>/dev/null | wc -l)
        TOTAL_DIRS=$(find "$WEB_ROOT" -type d 2>/dev/null | wc -l)
        TOTAL_SIZE=$(du -sh "$WEB_ROOT" 2>/dev/null | cut -f1)
        echo "  Tổng số file     : $TOTAL_FILES"
        echo "  Tổng số thư mục  : $TOTAL_DIRS"
        echo "  Tổng dung lượng  : $TOTAL_SIZE"
        echo ""

        # --- 2. Thống kê đuôi file (count + size) ---
        echo "--- [2] THỐNG KÊ THEO ĐỊNH DẠNG FILE ---"
        printf "  %-8s %-12s %s\n" "Số lượng" "Dung lượng" "Đuôi file"
        printf "  %-8s %-12s %s\n" "--------" "----------" "---------"

        # Lấy danh sách các đuôi file duy nhất
        find "$WEB_ROOT" -type f 2>/dev/null | grep -oE '\.[^./]+$' | \
            sort | uniq -c | sort -rn | head -20 | \
            while read count ext; do
                # Tính tổng dung lượng của đuôi file này
                size=$(find "$WEB_ROOT" -type f -name "*${ext}" 2>/dev/null \
                    -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1)
                # Chuyển bytes sang dạng human-readable
                if [[ $size -ge 1048576 ]]; then
                    size_hr="$(echo "scale=1; $size/1048576" | bc)MB"
                elif [[ $size -ge 1024 ]]; then
                    size_hr="$(echo "scale=1; $size/1024" | bc)KB"
                else
                    size_hr="${size}B"
                fi
                printf "  %-8s %-12s %s\n" "$count" "$size_hr" "$ext"
            done
        echo ""

        # --- 3. Top 5 thư mục lớn nhất ---
        echo "--- [3] TOP 5 THƯ MỤC LỚN NHẤT ---"
        printf "  %-10s %s\n" "Dung lượng" "Thư mục"
        printf "  %-10s %s\n" "----------" "-------"
        du -sh "${WEB_ROOT}"/*/  2>/dev/null | sort -rh | head -5 | \
            awk '{printf "  %-10s %s\n", $1, $2}'
        echo ""

        # --- 4. Top 10 file lớn nhất ---
        echo "--- [4] TOP 10 FILE LỚN NHẤT ---"
        printf "  %-10s %s\n" "Dung lượng" "File"
        printf "  %-10s %s\n" "----------" "----"
        find "$WEB_ROOT" -type f 2>/dev/null -exec du -sh {} + | \
            sort -rh | head -10 | \
            awk '{printf "  %-10s %s\n", $1, $2}'
        echo ""

        # --- 5. Thống kê file PHP ---
        echo "--- [5] THỐNG KÊ FILE PHP ---"
        PHP_COUNT=$(find "$WEB_ROOT" -name '*.php' 2>/dev/null | wc -l)
        PHP_SIZE=$(find "$WEB_ROOT" -name '*.php' 2>/dev/null \
            -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1)
        echo "  Tổng số file .php : $PHP_COUNT"
        echo "  Tổng dung lượng   : $(echo "scale=1; ${PHP_SIZE:-0}/1024/1024" | bc)MB"
        echo ""

        # --- 6. File sửa đổi gần nhất ---
        echo "--- [6] 5 FILE SỬA ĐỔI GẦN NHẤT ---"
        find "$WEB_ROOT" -type f 2>/dev/null -printf '%TY-%Tm-%Td %TH:%TM  %p\n' | \
            sort -r | head -5
        echo ""

        echo "================================================================"
        echo "  Báo cáo lưu tại: $REPORT_FILE"
        echo "  Hoàn tất lúc   : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "================================================================"

    } | tee "$REPORT_FILE"

    success "Phân tích hoàn tất! Xem báo cáo tại: $REPORT_FILE"
    log "Analyze report saved: $REPORT_FILE"
}

# ============================================================
# PHẦN TV3: MODULE SAO LƯU DỮ LIỆU
# ============================================================

_sync_to_s3() {
    if ! command -v aws &> /dev/null; then
        warn "CLI aws chưa được cài đặt, vui lòng chạy: apt install awscli"
        warn "Bỏ qua tiến trình đồng bộ S3."
        return
    fi

    info "Đang đồng bộ dữ liệu lên S3 bucket: s3://${S3_BUCKET_NAME}..."
    aws s3 sync "$BACKUP_DIR" "s3://${S3_BUCKET_NAME}/" --exclude "*.txt" 2>/dev/null
    if [ $? -eq 0 ]; then
        success "Đồng bộ S3 hoàn tất!"
    else
        warn "Đồng bộ S3 thất bại. Kiểm tra lại 'aws configure'."
    fi
}

_full_backup() {
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_PATH="${BACKUP_DIR}/full_${TIMESTAMP}"
    mkdir -p "$BACKUP_PATH"

    # Backup files
    info "Đang nén thư mục website..."
    tar -czf "${BACKUP_PATH}/web_files.tar.gz" \
        -C "$(dirname "$WEB_ROOT")" "$(basename "$WEB_ROOT")" 2>/dev/null || \
        error "Lỗi nén file"

    # Backup database
    info "Đang xuất database..."
    mysqldump -u root -p"${DB_ROOT_PASS}" \
        --single-transaction --routines --triggers \
        "${DB_NAME}" > "${BACKUP_PATH}/database.sql" || \
        error "Lỗi mysqldump"

    # Ghi metadata
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$LAST_BACKUP_FILE"
    echo "type=full"                     >> "$LAST_BACKUP_FILE"
    echo "path=${BACKUP_PATH}"           >> "$LAST_BACKUP_FILE"

    SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
    success "Full Backup hoàn tất: ${BACKUP_PATH} (${SIZE})"
    log "Full backup: ${BACKUP_PATH}"

    # Thực hiện đồng bộ lên S3
    _sync_to_s3
}

_incremental_backup() {
    if [[ ! -f "$LAST_BACKUP_FILE" ]]; then
        warn "Chưa có Full Backup. Tự động chạy Full Backup..."
        _full_backup
        return
    fi

    LAST_BACKUP_TIME=$(head -1 "$LAST_BACKUP_FILE")
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_PATH="${BACKUP_DIR}/incremental_${TIMESTAMP}"
    mkdir -p "$BACKUP_PATH"

    REFERENCE_FILE=$(mktemp)
    touch -d "$LAST_BACKUP_TIME" "$REFERENCE_FILE"

    # Tìm file thay đổi sau lần backup cuối
    info "Tìm file thay đổi sau: $LAST_BACKUP_TIME"
    # Dùng chuỗi mảng để lấy file list chuẩn xác
    CHANGED_FILES=$(find "$WEB_ROOT" -type f -newer "$REFERENCE_FILE" 2>/dev/null)
    
    # Đếm số lượng, xoá dòng rỗng để wc -l tính đúng
    if [[ -z "$CHANGED_FILES" ]]; then
        CHANGED_COUNT=0
    else
        CHANGED_COUNT=$(echo "$CHANGED_FILES" | grep -v '^$' | wc -l)
    fi

    if [[ $CHANGED_COUNT -eq 0 ]]; then
        warn "Không có file nào thay đổi. Bỏ qua backup."
        rm -f "$REFERENCE_FILE"
        return
    fi

    info "Tìm thấy ${CHANGED_COUNT} file thay đổi. Đang nén..."
    echo "$CHANGED_FILES" | tar -czf "${BACKUP_PATH}/changed_files.tar.gz" \
        --files-from=- 2>/dev/null || error "Lỗi nén incremental"

    # Lưu danh sách file đã backup
    echo "$CHANGED_FILES" > "${BACKUP_PATH}/file_list.txt"

    # Backup database
    mysqldump -u root -p"${DB_ROOT_PASS}" --single-transaction \
        "${DB_NAME}" > "${BACKUP_PATH}/database.sql"

    # Cập nhật thời gian backup cuối
    echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$LAST_BACKUP_FILE"
    echo "type=incremental"              >> "$LAST_BACKUP_FILE"
    rm -f "$REFERENCE_FILE"

    SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
    success "Incremental Backup hoàn tất: ${BACKUP_PATH} (${SIZE})"
    log "Incremental backup: ${BACKUP_PATH}, ${CHANGED_COUNT} files"

    # Thực hiện đồng bộ lên S3
    _sync_to_s3
}

backup_site() {
    info "=== BẮT ĐẦU SAO LƯU ==="
    check_disk_space 2
    [[ ! -d "$WEB_ROOT" ]] && error "Thư mục ${WEB_ROOT} không tồn tại!"
    mkdir -p "$BACKUP_DIR"

    echo ""
    echo "  1) Full Backup (toàn bộ)"
    echo "  2) Incremental Backup (file thay đổi)"
    read -rp "Chọn loại backup [1-2]: " backup_choice

    case $backup_choice in
        1) _full_backup ;;
        2) _incremental_backup ;;
        *) warn "Lựa chọn không hợp lệ"; return 1 ;;
    esac
}

# ============================================================
# PHẦN TV4: MENU CHÍNH VÀ HÀM main()
# ============================================================

show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   QUẢN LÝ WEBSITE OPENCART - NHÓM 8   ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "  1) Deploy   - Triển khai OpenCart"
    echo "  2) Analyze  - Phân tích hệ thống"
    echo "  3) Backup   - Sao lưu dữ liệu"
    echo "  4) Thoát"
    echo -e "${BLUE}----------------------------------------${NC}"
}

main() {
    check_root
    mkdir -p "$BACKUP_DIR" "$(dirname $LOG_FILE)"
    log "=== manage_web.sh khởi động ==="

    while true; do
        show_menu
        read -rp "Chọn chức năng [1-4]: " choice
        case $choice in
            1) deploy_site ;;
            2) analyze_site ;;
            3) backup_site ;;
            4) info "Thoát. Goodbye!"; exit 0 ;;
            *) warn "Lựa chọn không hợp lệ!" ;;
        esac
        read -rp "Nhấn Enter để tiếp tục..." _
    done
}

# Gọi hàm main
main

# Cấp quyền thực thi
# chmod +x manage_web.sh
# Chạy với quyền root
# sudo ./manage_web.sh