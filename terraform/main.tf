provider "azurerm" {
  features {}
  subscription_id = "cebfd57e-0155-4a3e-94b1-a4b0391baf14"
}

# Variables
#la localisation de nos ressources
variable "location" {
  default = "eastus"
}
# le nom de notre groupe de ressource
variable "resource_group_name" {
  default = "rg-private-aks-acr"
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Generate SSH Key Pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save Private Key Locally
resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/id_rsa"
  file_permission = "0600" # Ensure the private key is only readable by the owner
}

# VNet 1 (Bastion and VM Jumpbox)
resource "azurerm_virtual_network" "vnet1" {
  name                = "vnet1"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "vnet1_bastion_subnet" {
  name                 = "AzureBastionSubnet" # Required name for Bastion
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_subnet" "vnet1_vm_subnet" {
  name                 = "vm-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.1.2.0/24"]
}

# Azure Bastion
resource "azurerm_bastion_host" "bastion" {
  name                = "bastion-host"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku = "Standard"


  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = azurerm_subnet.vnet1_bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.bastion_pip.id
  }
}

resource "azurerm_public_ip" "bastion_pip" {
  name                = "bastion-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

}

# VM Jumpbox
resource "azurerm_network_interface" "vm_nic" {
  name                = "vm-jumpbox-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vnet1_vm_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vm_jumpbox" {
  name                = "vm-jumpbox"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.vm_nic.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}

# VNet 2 (AKS and ACR Private Endpoint)
resource "azurerm_virtual_network" "vnet2" {
  name                = "vnet2"
  address_space       = ["10.2.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "vnet2_aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = ["10.2.1.0/24"]
}

resource "azurerm_subnet" "vnet2_acr_subnet" {
  name                 = "acr-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = ["10.2.2.0/24"]
}

# Generate a random suffix for the ACR name
resource "random_string" "acr_suffix" {
  length  = 8
  special = false
  upper   = false
}

# ACR
resource "azurerm_container_registry" "acr" {
  name                = "acr${random_string.acr_suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Premium"
  admin_enabled       = true
  public_network_access_enabled = false
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "private-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "private-aks"

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name           = "default"
    node_count     = 1
    vm_size        = "Standard_D2_v2"
    vnet_subnet_id = azurerm_subnet.vnet2_aks_subnet.id
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.3.0.0/16"
    dns_service_ip = "10.3.0.10"
  }

  private_cluster_enabled = true
}


# ACR Private DNS Zone (created in the AKS-managed Resource Group)
resource "azurerm_private_dns_zone" "acr_dns_zone" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group # AKS-managed Resource Group
  depends_on = [azurerm_kubernetes_cluster.aks] # Ensure AKS cluster is created first
}
# ACR Private Endpoint (created in the AKS-managed Resource Group)
resource "azurerm_private_endpoint" "acr_private_endpoint" {
  name                = "acr-private-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group
  subnet_id           = azurerm_subnet.vnet2_acr_subnet.id
  private_service_connection {
    name                           = "acr-private-connection"
    private_connection_resource_id = azurerm_container_registry.acr.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }
  private_dns_zone_group {
    name                 = "acr-private-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr_dns_zone.id]
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}
# Link ACR DNS Zone to AKS Subnet
resource "azurerm_private_dns_zone_virtual_network_link" "acr_dns_link_aks_subnet" {
  name                  = "acr-dns-link-aks-subnet"
  resource_group_name   = azurerm_kubernetes_cluster.aks.node_resource_group
  private_dns_zone_name = azurerm_private_dns_zone.acr_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet2.id
  depends_on = [azurerm_private_dns_zone.acr_dns_zone]
}
# Link ACR DNS Zone to VM Subnet
resource "azurerm_private_dns_zone_virtual_network_link" "acr_dns_link_vm_subnet" {
  name                  = "acr-dns-link-vm-subnet"
  resource_group_name   = azurerm_kubernetes_cluster.aks.node_resource_group
  private_dns_zone_name = azurerm_private_dns_zone.acr_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet1.id # Link to VM subnet in VNet 1
  depends_on = [azurerm_private_dns_zone.acr_dns_zone] # Ensure DNS Zone is created first
}
# Retrieve the AKS Cluster Information
data "azurerm_kubernetes_cluster" "aks" {
  name                = azurerm_kubernetes_cluster.aks.name
  resource_group_name = azurerm_resource_group.rg.name
}

# Retrieve the AKS-managed resource group name
data "azurerm_resource_group" "aks_node_rg" {
  name = data.azurerm_kubernetes_cluster.aks.node_resource_group
}

# Extract the actual Private DNS Zone from the full FQDN
data "azurerm_private_dns_zone" "aks_dns_zone" {
  name                = join(".", slice(split(".", data.azurerm_kubernetes_cluster.aks.private_fqdn), 1, length(split(".", data.azurerm_kubernetes_cluster.aks.private_fqdn))))
  resource_group_name = data.azurerm_resource_group.aks_node_rg.name
}



# Link AKS API Server DNS Zone to VM Subnet // UPDATED
resource "azurerm_private_dns_zone_virtual_network_link" "aks_dns_link_vm_subnet" {
  name                  = "aks-dns-link-vm-subnet"
  resource_group_name   = data.azurerm_resource_group.aks_node_rg.name  # Use correct RG
  private_dns_zone_name = data.azurerm_private_dns_zone.aks_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet1.id

  depends_on = [azurerm_kubernetes_cluster.aks]
}


# VNet Peering
resource "azurerm_virtual_network_peering" "vnet1_to_vnet2" {
  name                      = "vnet1-to-vnet2"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.vnet1.name
  remote_virtual_network_id = azurerm_virtual_network.vnet2.id
  allow_forwarded_traffic = true
  allow_gateway_transit = true
}

resource "azurerm_virtual_network_peering" "vnet2_to_vnet1" {
  name                      = "vnet2-to-vnet1"
  resource_group_name       = azurerm_resource_group.rg.name
  virtual_network_name      = azurerm_virtual_network.vnet2.name
  remote_virtual_network_id = azurerm_virtual_network.vnet1.id
  allow_forwarded_traffic = true
  allow_gateway_transit = true
}


# Assign the AcrPull Role to the AKS Cluster's Managed Identity
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = data.azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}