# az_vnet.tf

resource "azurerm_virtual_network" "main" {
  name                = local.common_name
  address_space       = [local.vnet_cidr]
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags
}

resource "azurerm_subnet" "main" {
  name                 = "main"
  address_prefixes     = [local.subnet1_cidr]
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
}
