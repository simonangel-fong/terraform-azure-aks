locals {

  # ####################
  # Metadata
  # ####################
  project_name = "aks-demo"
  common_name  = "${local.project_name}-${var.env}"
  location     = "eastus"

  default_tags = {
    environment = var.env
    project     = "aks-demo"
    managed_by  = "terraform"
  }

  resource_group_name = "rg-${local.common_name}"

  # ####################
  # Aks
  # ####################
  aks_versions       = "1.35"
  aks_service_cidr   = "10.0.64.0/20"
  aks_dns_service_ip = "10.0.64.10"

  node_count   = 1
  node_vm_size = "Standard_B2s"

  # ####################
  # Networking
  # ####################
  vnet_cidr    = "10.10.0.0/16"
  subnet1_cidr = "10.10.0.0/20"  # 4,091
  subnet2_cidr = "10.10.32.0/20" # 4,091
}
