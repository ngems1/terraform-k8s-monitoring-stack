terraform {
  # 1.7+ for mock_provider in the native test framework.
  required_version = ">= 1.7.0"

  required_providers {
    helm = {
      source = "hashicorp/helm"
      # v3 of the provider changed its configuration syntax; this module is written for v2.
      version = ">= 2.12, < 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}
