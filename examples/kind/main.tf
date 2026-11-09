###############################################################################
# Try the whole stack on your laptop with kind (Kubernetes in Docker):
#
#   kind create cluster --name monitoring
#   terraform init && terraform apply
#   terraform output -raw grafana_admin_password
#   kubectl -n monitoring port-forward svc/monitoring-stack-grafana 3000:80
#   open http://localhost:3000  (user: admin)
#
# CI uses this same example for its end-to-end test.
###############################################################################

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}

module "monitoring" {
  source = "../../"

  cloud_provider = "generic"
  cluster_name   = "kind-local"

  # Small footprint for a laptop / CI runner.
  prometheus_storage_size   = "5Gi"
  alertmanager_storage_size = "1Gi"
  grafana_storage_size      = "1Gi"
  prometheus_resources = {
    requests = { cpu = "100m", memory = "512Mi" }
    limits   = { memory = "1536Mi" }
  }
  helm_timeout_seconds = 1200
}
