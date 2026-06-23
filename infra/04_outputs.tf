# outputs.tf

output "kubeconfig_command" {
  value = "az aks get-credentials -g ${azurerm_resource_group.main.name} -n ${azurerm_kubernetes_cluster.main.name} --file ./kubeconfig --overwrite-existing"
}
