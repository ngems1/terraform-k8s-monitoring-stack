output "grafana_port_forward" {
  description = "Open Grafana locally."
  value       = module.monitoring.port_forward_commands.grafana
}

output "grafana_admin_password" {
  description = "Grafana admin password (terraform output -raw grafana_admin_password)."
  value       = module.monitoring.grafana_admin_password
  sensitive   = true
}
