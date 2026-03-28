#!/bin/bash
# =================================================================
# Lịch Hẹn / Linux Hardware Information Collection Script
# Thu thập thông tin phần cứng: CPU, RAM, Disk, Network, Display
# =================================================================

# =================================================================
# CẤU HÌNH
# =================================================================
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
LOG_FILE="hardware_report_$(date '+%Y%m%d_%H%M%S').log"

# Chuyển hướng toàn bộ output (stdout và stderr) ra cả màn hình và file log
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "Đang thu thập thông tin và lưu log tại: $LOG_FILE\n"

# Màu sắc cho output (tùy chọn)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =================================================================
# HÀM HỖ TRỢ
# =================================================================

# Hàm in tiêu đề
print_header() {
    echo ""
    echo -e "${BLUE}================================================================================${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${BLUE}================================================================================${NC}"
}

# Hàm hiển thị thông tin trực tiếp ra màn hình
save_output() {
    echo -e "$1"
}

# Hàm kiểm tra lệnh tồn tại
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# =================================================================
# BẮT ĐẦU THU THẬP THÔNG TIN
# =================================================================

# Ghi thông tin header
save_output "${BLUE}================================================================================${NC}"
save_output "${GREEN}BÁO CÁO THÔNG TIN PHẦN CỨNG LINUX${NC}"
save_output "Được tạo lúc: $TIMESTAMP"
save_output "Tên máy (Hostname): $(hostname)"
save_output "${BLUE}================================================================================${NC}"

# =================================================================
# 1. THÔNG TIN HỆ THỐNG (System Information)
# =================================================================
print_header "1. THÔNG TIN HỆ THỐNG (SYSTEM)"
save_output ""
save_output "${GREEN}--- Tên Máy ---${NC}"
save_output "$(hostname)"
save_output ""

save_output "${GREEN}--- THÔNG TIN HỆ ĐIỀU HÀNH ---${NC}"
if [ -f /etc/os-release ]; then
    save_output "Tên Hệ điều hành: $(grep "^NAME=" /etc/os-release | cut -d'"' -f2)"
    save_output "Phiên bản Hệ điều hành: $(grep "^VERSION=" /etc/os-release | cut -d'"' -f2)"
    save_output "ID Hệ điều hành: $(grep "^ID=" /etc/os-release | cut -d'"' -f2)"
fi
save_output ""

save_output "${GREEN}--- THÔNG TIN KERNEL ---${NC}"
save_output "Nhân (Kernel): $(uname -r)"
save_output "Kiến trúc: $(uname -m)"
save_output ""

save_output "${GREEN}--- THỜI GIAN HOẠT ĐỘNG (UPTIME) ---${NC}"
save_output "$(uptime)"
save_output ""

# =================================================================
# 2. THÔNG TIN CPU
# =================================================================
print_header "2. THÔNG TIN CPU"
save_output ""

if command_exists lscpu; then
    save_output "${GREEN}--- THÔNG TIN CHI TIẾT CPU ---${NC}"
    save_output "Tên CPU: $(lscpu | grep -i "^Model name:" | cut -d':' -f2 | xargs)"
    save_output "Nhà sản xuất: $(lscpu | grep -i "^Vendor ID:" | cut -d':' -f2 | xargs)"
    save_output "Kiến trúc: $(lscpu | grep -i "^Architecture:" | cut -d':' -f2 | xargs)"
    save_output "Số lượng CPU: $(lscpu | grep -i "^CPU(s):" | cut -d':' -f2 | xargs)"
    save_output "Số luồng mỗi nhân: $(lscpu | grep -i "^Thread(s) per core:" | cut -d':' -f2 | xargs)"
    save_output "Số nhân mỗi socket: $(lscpu | grep -i "^Core(s) per socket:" | cut -d':' -f2 | xargs)"
    save_output "Số socket: $(lscpu | grep -i "^Socket(s):" | cut -d':' -f2 | xargs)"
    save_output "BogoMIPS: $(lscpu | grep -i "^BogoMIPS:" | cut -d':' -f2 | xargs)"
fi
save_output ""

# =================================================================
# 3. THÔNG TIN RAM/MEMORY
# =================================================================
print_header "3. THÔNG TIN RAM/MEMORY"
save_output ""

# Memory từ free
save_output "${GREEN}--- Bộ nhớ sử dụng (free -h) ---${NC}"
if command_exists free; then
    free -h | head -10
fi
save_output ""

# Memory từ /proc/meminfo
save_output "${GREEN}--- Bộ nhớ chi tiết (/proc/meminfo) ---${NC}"
if [ -f /proc/meminfo ]; then
    save_output "Bộ nhớ tổng cộng: $(grep MemTotal /proc/meminfo | awk '{printf "%.0f MB\n", $2/1024}')"
    save_output "Bộ nhớ trống: $(grep MemFree /proc/meminfo | awk '{printf "%.0f MB\n", $2/1024}')"
    save_output "Bộ nhớ có thể sử dụng: $(grep MemAvailable /proc/meminfo | awk '{printf "%.0f MB\n", $2/1024}')"
    save_output "Buffers: $(grep Buffers /proc/meminfo | awk '{printf "%.0f MB\n", $2/1024}')"
    save_output "Bộ nhớ đệm (Cached): $(grep Cached /proc/meminfo | head -1 | awk '{printf "%.0f MB\n", $2/1024}')"
    save_output "Tổng Swap: $(grep SwapTotal /proc/meminfo | awk '{printf "%.0f MB\n", $2/1024}')"
    save_output "Swap trống: $(grep SwapFree /proc/meminfo | awk '{printf "%.0f MB\n", $2/1024}')"
fi
save_output ""

# Memory chi tiết từ dmidecode (cần root)
save_output "${GREEN}--- RAM Modules ---${NC}"
if command_exists dmidecode; then
    if [ "$EUID" -eq 0 ]; then
        dmidecode -t memory 2>/dev/null | grep -E "Size:|Type:|Speed:|Manufacturer:|Part Number:|Serial Number:" | grep -viE "Unknown|Not Specified" | head -30
    else
        save_output "Hãy chạy script với quyền sudo (sudo $0) để xem chi tiết thanh RAM."
    fi
fi
save_output ""

# =================================================================
# 4. THÔNG TIN Ổ CỨNG/DISK
# =================================================================
print_header "4. THÔNG TIN Ổ CỨNG/DISK"
save_output ""

# Block devices
save_output "${GREEN}--- Thiết bị lưu trữ khối (lsblk) ---${NC}"
if command_exists lsblk; then
    lsblk -d -o NAME,SIZE,TYPE,ROTA,MODEL 2>/dev/null
fi
save_output ""

# Filesystems và usage
save_output "${GREEN}--- Tình trạng sử dụng phân vùng (df -h) ---${NC}"
if command_exists df; then
    df -h | grep -v "tmpfs\|devtmpfs\|loop\|Overlay"
fi
save_output ""
save_output ""

# =================================================================
# 5. THÔNG TIN GIAO DIỆN MẠNG (NETWORK)
# =================================================================
print_header "5. THÔNG TIN GIAO DIỆN MẠNG (NETWORK)"
save_output ""

# IP Addresses
save_output "${GREEN}--- Các địa chỉ IP ---${NC}"
if command_exists ip; then
    ip addr show
fi
save_output ""

# Network Interfaces (ngắn gọn)
save_output "${GREEN}--- Danh sách giao diện mạng (ip -br) ---${NC}"
if command_exists ip; then
    ip -br addr show
fi
save_output ""

# Routing Table
save_output "${GREEN}--- Bảng định tuyến cục bộ (ip route) ---${NC}"
if command_exists ip; then
    ip route
fi
save_output ""

# Network statistics
save_output "${GREEN}--- Thống kê lưu lượng mạng (ip -s link) ---${NC}"
if command_exists ip; then
    ip -s link
fi
save_output ""

# PCI Network devices
save_output "${GREEN}--- Thiết bị mạng gắn ngoài/PCI (lspci) ---${NC}"
if command_exists lspci; then
    lspci | grep -i "network\|ethernet"
fi
save_output ""

# Network driver info
save_output "${GREEN}--- Thông tin về thiết bị mạng (Driver Info) ---${NC}"
if [ -d /sys/class/net ]; then
    for iface in /sys/class/net/*; do
        iface_name=$(basename "$iface")
        save_output "Giao diện mạng: $iface_name"
        if [ -f "$iface/address" ]; then
            save_output "  Địa chỉ MAC: $(cat "$iface/address")"
        fi
        if [ -f "$iface/mtu" ]; then
            save_output "  MTU (Kích thước gói tin): $(cat "$iface/mtu")"
        fi
        if [ -f "$iface/operstate" ]; then
            save_output "  Trạng thái: $(cat "$iface/operstate")"
        fi
    done
fi
save_output ""

# =================================================================
# 6. THÔNG TIN ĐỒ HỌA/GPU (DISPLAY)
# =================================================================
print_header "6. THÔNG TIN ĐỒ HỌA/GPU (DISPLAY)"
save_output ""

# NVIDIA GPU
save_output "${GREEN}--- NVIDIA GPU (nvidia-smi) ---${NC}"
if command_exists nvidia-smi; then
    nvidia-smi
else
    save_output "Không khả dụng"
fi
save_output ""

# AMD GPU
save_output "${GREEN}--- AMD GPU (rocm-smi) ---${NC}"
if command_exists rocm-smi; then
    rocm-smi
else
    save_output "Không khả dụng"
fi
save_output ""

# Intel/AMD GPU từ lspci
save_output "${GREEN}--- Card đồ hoạ tích hợp / rời (lspci) ---${NC}"
if command_exists lspci; then
    lspci | grep -i "vga\|3d\|display\|graphics"
fi
save_output ""

# Xorg/Display info
save_output "${GREEN}--- Thông tin hiển thị màn hình (Xorg/Display) ---${NC}"
if command_exists xrandr; then
    XRANDR_OUT=$(xrandr 2>&1)
    if echo "$XRANDR_OUT" | grep -iq "Can't open display"; then
        save_output "Không có cấu hình kết nối màn hình hiển thị (thường xuất hiện ở môi trường dòng lệnh gốc/WSL)."
    else
        echo "$XRANDR_OUT"
    fi
elif command_exists hwinfo; then
    hwinfo --gfxcard --short
else
    save_output "Không có kết nối màn hình."
fi
save_output ""

# =================================================================
# 7. THÔNG TIN BO MẠCH CHỦ VÀ BIOS (MOTHERBOARD/BIOS)
# =================================================================
print_header "7. THÔNG TIN BO MẠCH CHỦ VÀ BIOS (MOTHERBOARD/BIOS)"
save_output ""

if command_exists dmidecode; then
    if [ "$EUID" -eq 0 ]; then
        save_output "${GREEN}--- Thông tin hệ thống ---${NC}"
        dmidecode -t system 2>/dev/null | grep -E "Manufacturer:|Product Name:|Serial Number:|UUID:"
        
        save_output "${GREEN}--- Bo mạch chủ (Motherboard) ---${NC}"
        dmidecode -t baseboard 2>/dev/null | grep -E "Manufacturer:|Product Name:|Serial Number:"
        
        save_output "${GREEN}--- Thông tin BIOS ---${NC}"
        dmidecode -t bios 2>/dev/null | grep -E "Vendor:|Version:|Release Date:"
    else
        save_output "Vui lòng chạy lệnh với quyền sudo (sudo $0) để xem chi tiết bo mạch."
    fi
fi
save_output ""

# =================================================================
# 8. THÔNG TIN THIẾT BỊ USB
# =================================================================
print_header "8. THÔNG TIN THIẾT BỊ USB"
save_output ""

save_output "${GREEN}--- Danh sách thiết bị kết nối USB (lsusb) ---${NC}"
if command_exists lsusb; then
    lsusb
fi
save_output ""

# =================================================================
# KẾT THÚC
# =================================================================
print_header "KẾT THÚC BÁO CÁO"
save_output ""
save_output "Thời gian hoàn tất báo cáo: $(date "+%Y-%m-%d %H:%M:%S")"
save_output ""

# Hiển thị thông báo hoàn tất
echo -e "${GREEN}================================================================================${NC}"
echo -e "${GREEN}✓ Hoàn tất thu thập thông tin phần cứng!${NC}"
echo -e "${GREEN}================================================================================${NC}"
echo ""

# Gợi ý chạy với sudo để xem đầy đủ
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Lưu ý: Bạn đang chạy với quyền người dùng thường.${NC}"
    echo -e "${YELLOW}   Một số thông số đặc biệt (như RAM, BIOS, SMART Disk) bị ẩn đi.${NC}"
    echo -e "${YELLOW}   Vui lòng chạy lại script với quyền root để xem toàn bộ thông tin:${NC}"
    echo "    sudo $0"
    echo ""
fi

exit 0
