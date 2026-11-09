###############################################################################
# Monitoring stack on an existing Google GKE cluster (Standard or Autopilot).
#   cp terraform.tfvars.example terraform.tfvars   # edit
#   terraform init && terraform apply
###############################################################################

provider "google" {
  project = var.project_id
}

# Short-lived access token of whoever runs Terraform (gcloud / service account).
data "google_client_config" "current" {}

data "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.location
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.this.endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.this.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.this.endpoint}"
    token                  = data.google_client_config.current.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.this.master_auth[0].cluster_ca_certificate)
  }
}

module "monitoring" {
  source = "../../"

  cloud_provider    = "gke"
  gke_autopilot     = var.autopilot
  cluster_name      = var.cluster_name
  slack_webhook_url = var.slack_webhook_url
}
