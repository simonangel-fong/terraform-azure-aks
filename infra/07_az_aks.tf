# az_aks.tf

# IAM
# used to authenticate applications and services without managing hardcoded credentials or secrets
resource "azurerm_user_assigned_identity" "base" {
  name                = "base"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

resource "azurerm_role_assignment" "base" {
  principal_id         = azurerm_user_assigned_identity.base.principal_id
  role_definition_name = "Network Contributor"
  scope                = azurerm_resource_group.main.id
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = local.common_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = local.project_name

  kubernetes_version        = local.aks_versions
  automatic_upgrade_channel = "stable"
  private_cluster_enabled   = false
  node_resource_group       = local.common_name

  sku_tier = "Free"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  network_profile {
    network_plugin = "azure"
    dns_service_ip = local.aks_dns_service_ip
    service_cidr   = local.aks_service_cidr
  }

  default_node_pool {
    name       = "general"
    node_count = 1
    vm_size    = "standard_d2ds_v7"

    node_labels = {
      role = "general"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.base.id]
  }

  tags = local.default_tags

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]
  }

  depends_on = [
    azurerm_role_assignment.base
  ]
}
