# ============================================================================
# main.tf - Hạ tầng chính cho CIS AKS Benchmark
# ----------------------------------------------------------------------------
# Resources được tạo:
#   1. (Data) Reference tới Resource Group AzureStudentLab đã tồn tại
#   2. Virtual Network + Subnet (mới)
#   3. Log Analytics Workspace (mới)
#   4. AKS Cluster (mới)
# ============================================================================

# ============================================================================
# 1. TERRAFORM SETTINGS + AZURE PROVIDER
# ============================================================================
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # Cho phép xóa Resource Group kể cả khi còn resource bên trong
      prevent_deletion_if_contains_resources = false
    }
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ============================================================================
# 3. VIRTUAL NETWORK + SUBNET
# ----------------------------------------------------------------------------
# Tự tạo VNet thay vì để AKS tự tạo để:
#   - Kiểm soát CIDR, subnet (cần cho controls 5.4.x)
#   - Chứng minh hiểu networking
#   - Có thể thêm NSG sau khi cần remediation
# ============================================================================
resource "azurerm_virtual_network" "main" {
  name                = "vnet-aks-audit"
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks-nodes"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.aks_subnet_address_prefix
}

# ============================================================================
# 4. LOG ANALYTICS WORKSPACE
# ----------------------------------------------------------------------------
# Cần cho OMS Agent (monitoring) và controls 5.1.x (logging/auditing).
# Cluster mẫu của bạn KHÔNG bật Container Insights, nhưng audit cần nó
# để PASS các controls thuộc nhóm logging.
# ============================================================================
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-aks-audit"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

# ============================================================================
# 5. AKS CLUSTER
# ----------------------------------------------------------------------------
# Cấu hình được chọn để phục vụ audit:
#
#   Tham số                       | Giá trị         | Control phục vụ
#   ------------------------------|-----------------|---------------------
#   network_plugin                | azure (CNI)     | 4.4.1, 5.4.4
#   network_policy                | calico          | 5.4.4, 4.4.2
#   linux_profile.ssh_key         | aks-key.pub     | 3.1.x, 3.2.x
#   authorized_ip_ranges          | (cấu hình sau)  | 5.4.1
#   enable_node_public_ip         | false           | 5.4.3
#   role_based_access_control     | true            | 4.1.x
#   oms_agent                     | Enabled         | 5.1.x
#
# ============================================================================
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  # -------- Default Node Pool --------
  default_node_pool {
    name                  = "system"
    node_count            = var.node_count
    vm_size               = var.vm_size
    vnet_subnet_id        = azurerm_subnet.aks.id
    os_disk_type          = "Ephemeral"
    os_disk_size_gb       = 30
    enable_node_public_ip = false # Control 5.4.3
    type                  = "VirtualMachineScaleSets"
    enable_auto_scaling   = false # Cố định node count để dễ kiểm soát chi phí
  }

  # -------- Identity --------
  identity {
    type = "SystemAssigned"
  }

  # -------- Linux Profile (SSH access cho audit) --------
  linux_profile {
    admin_username = var.admin_username

    ssh_key {
      # pathexpand() xử lý "~" thành home directory.
      # Dùng thêm trimspace() và replace() với mã \ufeff để loại bỏ ký tự BOM.
      # Khoảng trắng/xuống dòng thừa cũng được xử lý để tránh lỗi 400 từ Azure.
      key_data = trimspace(replace(file(pathexpand(var.ssh_public_key_path)), "\ufeff", ""))
    }
  }

  # -------- Network Profile --------
  # Azure CNI + Calico là bắt buộc cho controls 4.4.x và 5.4.4
  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
    load_balancer_sku = "standard"
  }

  # -------- API Server Access Control (Control 5.4.1) --------
  # Khi authorized_ip_ranges rỗng: API Server public (để setup dễ).
  # Sau khi cluster chạy, dùng lệnh az aks update để set IP:
  #   az aks update -g rg-cis-aks-audit -n aks-cis-audit \
  #     --api-server-authorized-ip-ranges "IP/32"
  # Để clear:
  #   az aks update -g rg-cis-aks-audit -n aks-cis-audit \
  #     --api-server-authorized-ip-ranges ""
  dynamic "api_server_access_profile" {
    for_each = length(var.authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.authorized_ip_ranges
    }
  }

  # -------- Monitoring / OMS Agent --------
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # -------- Role-Based Access Control --------
  role_based_access_control_enabled = true

  tags = var.tags

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
      # authorized_ip_ranges được quản lý bằng az aks update (ngoài Terraform)
      # vì mạng CGNAT có nhiều exit IP động. Xem comment ở api_server_access_profile.
      api_server_access_profile,
    ]
  }
}