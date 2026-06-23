# az_vnet.tf

resource "azurerm_virtual_network" "main" {
  name                = local.common_name
  address_space       = [local.vnet_cidr]
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags
}

resource "azurerm_subnet" "subnet1" {
  name                 = "subnet1"
  address_prefixes     = [local.subnet1_cidr]
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
}

resource "azurerm_subnet" "subnet2" {
  name                 = "subnet2"
  address_prefixes     = [local.subnet2_cidr]
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
}
