# outputs.tf

output "kubeconfig_command" {
  value = "az aks get-credentials -g ${azurerm_resource_group.main.name} -n ${azurerm_kubernetes_cluster.main.name} --file ./kubeconfig --overwrite-existing"
}

output "argocd_admin_password_command" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_command" {
  value = "kubectl -n argocd port-forward svc/argocd-server 8080:443"
}
