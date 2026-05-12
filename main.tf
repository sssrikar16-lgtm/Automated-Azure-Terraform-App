provider "azurerm" {
  subscription_id = "<subscription_id>"
  client_id       = "<client_id>"
  client_secret   = "<client_secret>"
  tenant_id       = "<tenant_id>"
}

# Create a resource group
resource "azurerm_resource_group" "autoscaling_group_rg" {
  name     = "autoscaling_group_rg"
  location = "eastus"
}

# Create a virtual network and subnet
resource "azurerm_virtual_network" "autoscaling_group_vnet" {
  name                = "autoscaling_group_vnet"
  address_space       = ["10.0.0.0/16"]
  location            = "eastus"
  resource_group_name = azurerm_resource_group.autoscaling_group_rg.name

  subnet {
    name           = "autoscaling_group_subnet"
    address_prefix = "10.0.1.0/24"
  }
}

# Create a load balancer
resource "azurerm_lb" "autoscaling_group_lb" {
  name                = "autoscaling_group_lb"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.autoscaling_group_rg.name

  frontend_ip_configuration {
    name                          = "PublicIPAddress"
    public_ip_address_id          = azurerm_public_ip.autoscaling_group_pip.id
    private_ip_address_allocation = "Dynamic"
  }

  backend_address_pool {
    name = "autoscaling_group_backend_pool"
  }

  probe {
    name                = "autoscaling_group_probe"
    interval_in_seconds = 5
    number_of_probes    = 2
    port                = 80
    protocol            = "Http"
    request_path        = "/"
  }
}

# Create a public IP address for the load balancer
resource "azurerm_public_ip" "autoscaling_group_pip" {
  name                = "autoscaling_group_pip"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.autoscaling_group_rg.name
  allocation_method   = "Static"
}

# Create a network security group for the autoscaling group instances
resource "azurerm_network_security_group" "autoscaling_group_nsg" {
  name                = "autoscaling_group_nsg"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.autoscaling_group_rg.name

  security_rule {
    name                       = "AllowHTTPInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSHInbound"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create an availability set for the autoscaling group instances
resource "azurerm_availability_set" "autoscaling_group_as" {
  name                = "autoscaling_group_as"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.autoscaling_group_rg.name
}

# Create an autoscaling group with a minimum of 2 instances and a maximum of 5 instances
resource "azurerm_virtual_machine_scale_set" "autoscaling_group" {
  name                = "autoscaling_group"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.autoscaling_group_rg.name
  sku                 = "Standard_DS1_v2"
  instances           = 2

  upgrade_policy {
    mode = "Manual"
  }

  network_profile {
    name    = "autoscaling_group_network_profile"
    primary = true

    network_interface {
      name    = "autoscaling_group_nic"
      primary = true

      ip_configuration {
        name                          = "autoscaling_group_ip_config"
        subnet_id                     = azurerm_virtual_network.autoscaling_group_vnet.subnet.id
        load_balancer_backend_address_pool_ids = [azurerm_lb.autoscaling_group_lb.backend_address_pool_id]
        load_balancer_inbound_nat_rules_ids     = [azurerm_lb_nat_rule.autoscaling_group_nat_rule.id]
        public_ip_address_id          = azurerm_public_ip.autoscaling_group_pip.id
      }
    }
  }

  os_profile {
    computer_name_prefix = "autoscaling-group"
    admin_username       = "adminuser"
    admin_password= "<your_admin_password>"
  }

  availability_set_id = azurerm_availability_set.autoscaling_group_as.id

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_profile_os_disk {
    name              = "autoscaling_group_os_disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  # Autoscaling configuration
  automatic_repairs_policy {
    enabled = true
  }

  automatic_os_upgrade {
    enable_automatic_os_upgrade = true
  }

  upgrade_policy {
    mode = "Automatic"
  }

  scaling_policy {
    name          = "autoscaling_policy"
    mode          = "Automatic"
    cooldown      = "PT10M"
    metric_trigger {
      metric_name        = "Percentage CPU"
      metric_resource_id = azurerm_virtual_machine_scale_set.autoscaling_group.id
      time_grain         = "PT1M"
      statistic          = "Average"
      time_window        = "PT5M"
      operator           = "GreaterThan"
      threshold          = 70
    }
    scaling_rule {
      direction         = "Increase"
      type              = "ChangeCount"
      value             = "1"
      cooldown          = "PT5M"
      metric_trigger_id = scaling_policy.metric_trigger[0].id
    }
    scaling_rule {
      direction         = "Decrease"
      type              = "PercentChangeCount"
      value             = "20"
      cooldown          = "PT5M"
      metric_trigger_id = scaling_policy.metric_trigger[0].id
    }
  }
}

# Create a load balancer NAT rule
resource "azurerm_lb_nat_rule" "autoscaling_group_nat_rule" {
  name                = "autoscaling_group_nat_rule"
  resource_group_name = azurerm_resource_group.autoscaling_group_rg.name
  load_balancer_id    = azurerm_lb.autoscaling_group_lb.id
  protocol            = "Tcp"
  frontend_port       = 80
  backend_port        = 80
  frontend_ip_configuration_id = azurerm_lb.autoscaling_group_lb.frontend_ip_configuration[0].id
}