# ============================================================================
# variables.tf - Khai báo các biến đầu vào cho Terraform
# Dự án: CIS AKS Benchmark v1.8.0 - NT542
# ----------------------------------------------------------------------------

# ============================================================================
# === PHẦN A: CẤU HÌNH PHẦN CỨNG + LOCATION ===
# ============================================================================

variable "resource_group_name" {
  description = <<-EOT
    Tên Resource Group chứa tất cả tài nguyên.
  EOT
  type        = string
  default     = "rg-cis-aks-audit"
}

variable "location" {
  description = <<-EOT
    Azure region. Bắt buộc dùng japanwest vì subscription Azure for Students.
  EOT
  type        = string
  default     = "japanwest"
}

variable "cluster_name" {
  description = "Tên AKS cluster cho dự án audit"
  type        = string
  default     = "aks-cis-audit"
}

variable "kubernetes_version" {
  description = <<-EOT
    Phiên bản Kubernetes. Dùng 1.33.7 vì đã verify chạy được trên
    subscription Azure for Students qua cluster mẫu.
  EOT
  type        = string
  default     = "1.33.7"
}

variable "node_count" {
  description = "Số worker nodes - 1"
  type        = number
  default     = 1
}

variable "vm_size" {
  description = <<-EOT
    VM size cho worker nodes.
    Standard_D2s_v3 = 2 vCPU / 8GB RAM.
    KHÔNG đổi sang Standard_B2s vì subscription chỉ cho sử dụng loại D, loại B không dựng Cluster được.
  EOT
  type        = string
  default     = "Standard_D2s_v3"
}

# ============================================================================
# === PHẦN B: CẤU HÌNH BẢO MẬT + MẠNG (theo yêu cầu CIS Benchmark) ===
# ============================================================================

variable "ssh_public_key_path" {
  description = <<-EOT
    Đường dẫn tới SSH public key (tạo ở Week 1 - aks-key.pub).
    Bắt buộc cho controls 3.1.x và 3.2.x - cần SSH vào node để
    kiểm tra file permissions và kubelet config.
  EOT
  type        = string
  default     = "./.ssh/aks-key.pub"
}

variable "admin_username" {
  description = "Username admin trên Linux node để SSH vào audit"
  type        = string
  default     = "azureuser"
}

variable "authorized_ip_ranges" {
  description = <<-EOT
    Danh sách IP ranges được phép truy cập API Server (Control 5.4.1).
    Ban đầu để rỗng để không bị khóa trong setup.
    Sau khi cluster chạy, lấy IP của nhóm bằng: truy cập trang ifconfig.me
    Rồi cập nhật bằng:
      terraform apply -var='authorized_ip_ranges=["IP_ADDRESS"]'
    Để control 5.4.1 PASS.
  EOT
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = <<-EOT
    Số ngày giữ log trong Log Analytics Workspace.
    Cần cho controls thuộc nhóm 5.1.x (logging và monitoring).
  EOT
  type        = number
  default     = 30
}

# ============================================================================
# === PHẦN C: CẤU HÌNH KHÔNG GIAN ĐỊA CHỈ MẠNG ===
# ----------------------------------------------------------------------------
# CHỌN Azure CNI (không phải Overlay) vì:
#   - Cần có VNet/Subnet riêng để chứng minh hiểu networking
#   - Cho phép kiểm soát chi tiết hơn cho audit 4.4.x
#   - Tương thích đầy đủ với Calico network policy
# ============================================================================

variable "vnet_address_space" {
  description = "CIDR cho Virtual Network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_address_prefix" {
  description = "CIDR cho subnet chứa AKS nodes"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "service_cidr" {
  description = "CIDR cho Kubernetes services (ClusterIP). Phải KHÁC vnet_address_space"
  type        = string
  default     = "10.1.0.0/16"
}

variable "dns_service_ip" {
  description = "IP của kube-dns service. Phải nằm trong service_cidr"
  type        = string
  default     = "10.1.0.10"
}

# ============================================================================
# === PHẦN D: TAGS ===
# ============================================================================

variable "tags" {
  description = "Tags gắn vào mọi tài nguyên Azure"
  type        = map(string)
  default = {
    project     = "CIS-AKS-Benchmark"
    environment = "lab"
    managed_by  = "terraform"
    course      = "NT542"
  }
}