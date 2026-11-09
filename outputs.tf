output "namespace" {
  description = "Namespace the stack runs in."
  value       = local.namespace
}

output "release_name" {
  description = "Helm release name (also the resource name prefix)."
  value       = helm_release.this.name
}

output "chart_version" {
  description = "Deployed kube-prometheus-stack chart version."
  value       = helm_release.this.version
}

output "storage_class" {
  description = "StorageClass used for the stack's volumes (null = cluster default)."
  value       = local.storage_class
}

output "grafana_admin_secret_name" {
  description = "Kubernetes Secret holding the Grafana admin user and password."
  value       = kubernetes_secret_v1.grafana_admin.metadata[0].name
}

output "grafana_admin_password" {
  description = "Grafana admin password (terraform output -raw grafana_admin_password)."
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "grafana_url" {
  description = "Grafana URL when the ingress is enabled, otherwise null (use port_forward_commands)."
  value       = var.grafana_ingress.enabled ? "${var.grafana_ingress.tls_secret_name == "" ? "http" : "https"}://${var.grafana_ingress.host}" : null
}

output "service_names" {
  description = "In-cluster service names (DNS: <name>.<namespace>.svc)."
  value = {
    prometheus   = "${var.release_name}-prometheus"
    alertmanager = "${var.release_name}-alertmanager"
    grafana      = "${var.release_name}-grafana"
  }
}

output "port_forward_commands" {
  description = "Commands to open each UI locally without exposing it publicly."
  value = {
    grafana      = "kubectl -n ${local.namespace} port-forward svc/${var.release_name}-grafana 3000:80"
    prometheus   = "kubectl -n ${local.namespace} port-forward svc/${var.release_name}-prometheus 9090:9090"
    alertmanager = "kubectl -n ${local.namespace} port-forward svc/${var.release_name}-alertmanager 9093:9093"
  }
}

output "alert_rule_groups" {
  description = "Names of the extra rule groups loaded by this module."
  value       = sort(flatten([for name, r in local.prometheus_rules : [for g in r.groups : g.name]]))
}
