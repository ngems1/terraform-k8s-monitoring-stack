###############################################################################
# Monitoring stack on an existing Amazon EKS cluster.
#   cp terraform.tfvars.example terraform.tfvars   # edit
#   terraform init && terraform apply
# Prerequisite: the EKS "Amazon EBS CSI driver" add-on (for the gp3 volumes).
###############################################################################

provider "aws" {
  region = var.region
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# The helm and kubernetes providers talk to the cluster API. `exec` fetches a
# fresh token on every call, so long Helm installs never hit token expiry.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
    }
  }
}

module "monitoring" {
  source = "../../"

  cloud_provider    = "eks"
  cluster_name      = var.cluster_name
  slack_webhook_url = var.slack_webhook_url
}
