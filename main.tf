terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

resource "azurerm_resource_group" "rg-atv" {
  name     = "atv"
  location = "East US"
}

resource "azurerm_virtual_network" "vnet-atv" {
  name                = "vnet-atv"
  location            = azurerm_resource_group.rg-atv.location
  resource_group_name = azurerm_resource_group.rg-atv.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "sub-atv" {
  name                 = "sub-atv"
  resource_group_name  = azurerm_resource_group.rg-atv.name
  virtual_network_name = azurerm_virtual_network.vnet-atv.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "ip-atv" {
  name                = "ip-atv"
  resource_group_name = azurerm_resource_group.rg-atv.name
  location            = azurerm_resource_group.rg-atv.location
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "nsg-atv" {
  name                = "nsg-atv"
  location            = azurerm_resource_group.rg-atv.location
  resource_group_name = azurerm_resource_group.rg-atv.name

  security_rule {
    name                       = "web"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "nic-atv" {
  name                = "nic-atv"
  location            = azurerm_resource_group.rg-atv.location
  resource_group_name = azurerm_resource_group.rg-atv.name

  ip_configuration {
    name                          = "ip-atv-nic"
    subnet_id                     = azurerm_subnet.sub-atv.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip-atv.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic-nsg-atv" {
  network_interface_id      = azurerm_network_interface.nic-atv.id
  network_security_group_id = azurerm_network_security_group.nsg-atv.id
}

resource "azurerm_storage_account" "mystorageaccount" {
  name                     = "storageaccountmyvm"
  resource_group_name      = azurerm_resource_group.rg-atv.name
  location                 = azurerm_resource_group.rg-atv.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_virtual_machine" "vm-atv" {
  name                  = "vm-atv"
  location              = azurerm_resource_group.rg-atv.location
  resource_group_name   = azurerm_resource_group.rg-atv.name
  network_interface_ids = [azurerm_network_interface.nic-atv.id]
  vm_size               = "Standard_DS1_v2"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "hostname"
    admin_username = "admin"
    admin_password = "password"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }
}

resource "null_resource" "install-apache" {
  connection {
    type     = "ssh"
    host     = azurerm_public_ip.ip-atv.ip_address
    user     = "admin"
    password = "password"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install -y apache2",
    ]
  }

  depends_on = [
    azurerm_virtual_machine.vm-atv
  ]
}

resource "null_resource" "upload-app" {
  connection {
    type     = "ssh"
    host     = azurerm_public_ip.ip-atv.ip_address
    user     = "admin"
    password = "password"
  }

  provisioner "file" {
    source      = "app"
    destination = "/home/testeadmin"
  }

  depends_on = [
    azurerm_virtual_machine.vm-atv
  ]
}