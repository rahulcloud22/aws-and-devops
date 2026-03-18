resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.application_name}"
  location            = "eastus"
  resource_group_name = var.resource_group_name
  address_space       = ["172.31.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["172.31.0.0/24"]
}

resource "azurerm_subnet" "public_subnets" {
  for_each             = { for subnet in range(2) : subnet + 1 => {} }
  name                 = "public-subnet-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["172.31.${each.key}.0/24"]
}

resource "azurerm_subnet" "private_subnets" {
  for_each             = { for subnet in range(2) : subnet + 1 => {} }
  name                 = "private-subnet-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["172.31.${10 + each.key}.0/24"]
}

module "public_ipaddress" {
  source              = "../../azure/public_ipaddress"
  resource_group_name = var.resource_group_name
  application_name    = var.application_name
  location            = "eastus"
  tags                = var.tags
}

module "vnet_gateway" {
  source              = "../../azure/virtual_network_gateway"
  resource_group_name = var.resource_group_name
  application_name    = var.application_name
  location            = "eastus"
  sku                 = "VpnGw3"
  tags                = var.tags
  ip_configurations = [{
    subnet_id            = azurerm_subnet.gateway.id
    public_ip_address_id = module.public_ipaddress.id
  }]
}

resource "azurerm_local_network_gateway" "aws" {
  name                = "aws-gateway"
  location            = "eastus"
  resource_group_name = var.resource_group_name
  gateway_address     = aws_vpn_connection.tgw_vpn.tunnel1_address
  address_space       = [module.vpc_a_east.vpc_cidr, module.vpc_b_east.vpc_cidr] # AWS VPC CIDR
}

resource "azurerm_virtual_network_gateway_connection" "vpn" {
  name                       = "azure-to-aws"
  location                   = "eastus"
  resource_group_name        = var.resource_group_name
  type                       = "IPsec"
  virtual_network_gateway_id = module.vnet_gateway.id
  local_network_gateway_id   = azurerm_local_network_gateway.aws.id
  shared_key                 = aws_vpn_connection.tgw_vpn.tunnel1_preshared_key
}

resource "azurerm_route_table" "to_aws" {
  name                = "rt-to-aws"
  location            = "eastus"
  resource_group_name = var.resource_group_name
}

resource "azurerm_route" "aws" {
  name                = "aws-via-vpn"
  resource_group_name = var.resource_group_name
  route_table_name    = azurerm_route_table.to_aws.name
  address_prefix      = module.vpc_a_east.vpc_cidr
  next_hop_type       = "VirtualNetworkGateway"
}

resource "azurerm_route" "aws_b" {
  name                = "aws-b-via-vpn"
  resource_group_name = var.resource_group_name
  route_table_name    = azurerm_route_table.to_aws.name
  address_prefix      = module.vpc_b_east.vpc_cidr
  next_hop_type       = "VirtualNetworkGateway"
}

resource "azurerm_subnet_route_table_association" "app" {
  subnet_id      = azurerm_subnet.public_subnets[1].id
  route_table_id = azurerm_route_table.to_aws.id
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "vm-nic"
  location            = "eastus"
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public_subnets[1].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip.id
  }
}

resource "azurerm_public_ip" "vm_pip" {
  name                = "vm-pip"
  location            = "eastus"
  resource_group_name = var.resource_group_name

  allocation_method = "Static"
  sku               = "Standard"
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.vm_nic.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}


resource "azurerm_linux_virtual_machine" "cheap_vm" {
  name                            = "cheap-vm"
  location                        = "eastus"
  resource_group_name             = var.resource_group_name
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.vm_nic.id
  ]
  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/Documents/keypair.pub")
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # cheapest disk
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

resource "azurerm_network_security_group" "vm_nsg" {
  name                = "vm-nsg"
  location            = "eastus"
  resource_group_name = var.resource_group_name
  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    destination_port_range     = "22"
    source_port_range          = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "allow-from-aws"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefixes    = ["10.10.0.0/16", "10.50.0.0/16"]
    destination_port_range     = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
  }
}