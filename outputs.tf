# Output the resource group name
output "resource_group_name" {
  value       = azurerm_resource_group.autoscaling_group_rg.name
  description = "The name of the created Azure resource group"
}

# Output the load balancer public IP
output "load_balancer_public_ip" {
  value       = azurerm_public_ip.autoscaling_group_pip.ip_address
  description = "The public IP address of the load balancer"
}

# Output the backend address pool ID
output "backend_address_pool_id" {
  value       = azurerm_lb.autoscaling_group_lb.backend_address_pool[0].id
  description = "The ID of the backend address pool"
}
