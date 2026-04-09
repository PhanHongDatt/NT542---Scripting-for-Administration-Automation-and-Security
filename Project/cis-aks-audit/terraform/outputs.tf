# ============================================================================
# outputs.tf - Các giá trị xuất ra sau khi terraform apply
# ============================================================================

output "resource_group_name" {
  description = "Tên Resource Group đang dùng"
  value       = azurerm_resource_group.main.name
}

output "cluster_name" {
  description = "Tên AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_location" {
  description = "Azure region nơi cluster được tạo"
  value       = azurerm_kubernetes_cluster.main.location
}

output "kubernetes_version" {
  description = "Phiên bản Kubernetes đang chạy"
  value       = azurerm_kubernetes_cluster.main.kubernetes_version
}

output "node_vm_size" {
  description = "VM size của worker nodes"
  value       = azurerm_kubernetes_cluster.main.default_node_pool[0].vm_size
}

output "kube_config_command" {
  description = "Lệnh để lấy kubeconfig và kết nối kubectl tới cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name} --overwrite-existing"
}

output "ssh_to_node_command" {
  description = "Lệnh SSH vào worker node qua kubectl debug"
  value       = "kubectl debug node/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') -it --image=mcr.microsoft.com/cbl-mariner/busybox:2.0"
}

output "stop_cluster_command" {
  description = "Lệnh stop cluster để tiết kiệm chi phí"
  value       = "az aks stop --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "start_cluster_command" {
  description = "Lệnh start cluster khi cần làm việc"
  value       = "az aks start --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "network_config_summary" {
  description = "Tóm tắt cấu hình network cho audit controls 4.4.x, 5.4.x"
  value = {
    network_plugin = azurerm_kubernetes_cluster.main.network_profile[0].network_plugin
    network_policy = azurerm_kubernetes_cluster.main.network_profile[0].network_policy
    service_cidr   = azurerm_kubernetes_cluster.main.network_profile[0].service_cidr
    pod_cidr       = "Azure CNI - mỗi pod lấy IP từ subnet ${azurerm_subnet.aks.address_prefixes[0]}"
  }
}