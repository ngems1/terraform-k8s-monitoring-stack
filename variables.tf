###############################################################################
# Where are we deploying?
###############################################################################

variable "cloud_provider" {
  description = "Kubernetes flavour: eks, aks, gke or generic (self-managed / kind / k3s). Drives storage class and control-plane defaults."
  type        = string

  validation {
    condition     = contains(["eks", "aks", "gke", "generic"], var.cloud_provider)
    error_message = "cloud_provider must be one of: eks, aks, gke, generic."
  }
}

variable "gke_autopilot" {
  description = "Set true for GKE Autopilot clusters, which forbid the host access node-exporter needs (node-level metrics are then unavailable)."
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Added as the `cluster` label to every metric and alert, so notifications say which cluster they come from."
  type        = string
  default     = ""
}

###############################################################################
# Release
###############################################################################

variable "namespace" {
  description = "Namespace for the monitoring stack."
  type        = string
  default     = "monitoring"
}

variable "create_namespace" {
  description = "Create the namespace (with Pod Security labels). Set false if it is managed elsewhere."
  type        = bool
  default     = true
}

variable "release_name" {
  description = "Helm release name; also the prefix of every resource (e.g. <release>-prometheus). Keep it short."
  type        = string
  default     = "monitoring-stack"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,24}$", var.release_name))
    error_message = "release_name must be lowercase, start with a letter and be at most 25 characters (Kubernetes name limits)."
  }
}

variable "chart_version" {
  description = "kube-prometheus-stack chart version (pinned for reproducible deploys)."
  type        = string
  default     = "79.7.1"
}

variable "chart_repository" {
  description = "Helm repository for kube-prometheus-stack (override for an internal mirror)."
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
}

variable "helm_timeout_seconds" {
  description = "How long Helm waits for all pods to become ready before rolling back."
  type        = number
  default     = 900
}

###############################################################################
# Storage & sizing
###############################################################################

variable "storage_class_name" {
  description = "StorageClass for Prometheus, Alertmanager and Grafana volumes. Null picks a sensible default per cloud (eks: gp3, aks: managed-csi, gke: standard-rwo, generic: cluster default)."
  type        = string
  default     = null
}

variable "create_eks_gp3_storage_class" {
  description = "On EKS, create an encrypted gp3 StorageClass (EKS only ships gp2). Requires the EBS CSI driver add-on."
  type        = bool
  default     = true
}

variable "prometheus_retention" {
  description = "How long Prometheus keeps metrics (e.g. 15d, 720h)."
  type        = string
  default     = "15d"

  validation {
    condition     = can(regex("^[0-9]+(h|d|w|y)$", var.prometheus_retention))
    error_message = "prometheus_retention must look like 15d, 720h, 4w or 1y."
  }
}

variable "prometheus_storage_size" {
  description = "Size of the Prometheus volume. Prometheus also deletes old data once 90% of it is used, so the disk never fills."
  type        = string
  default     = "50Gi"

  validation {
    condition     = can(regex("^[0-9]+Gi$", var.prometheus_storage_size))
    error_message = "prometheus_storage_size must be in Gi, e.g. 50Gi."
  }
}

variable "prometheus_replicas" {
  description = "Prometheus replicas (2 gives high availability; each keeps a full copy of the data)."
  type        = number
  default     = 1

  validation {
    condition     = var.prometheus_replicas >= 1 && var.prometheus_replicas <= 3
    error_message = "prometheus_replicas must be between 1 and 3."
  }
}

variable "prometheus_resources" {
  description = "CPU/memory requests and limits for Prometheus. Memory grows with the number of time series."
  type = object({
    requests = map(string)
    limits   = map(string)
  })
  default = {
    requests = { cpu = "500m", memory = "2Gi" }
    limits   = { memory = "4Gi" }
  }
}

variable "alertmanager_storage_size" {
  description = "Size of the Alertmanager volume (silences and notification state)."
  type        = string
  default     = "5Gi"
}

variable "grafana_storage_size" {
  description = "Size of the Grafana volume (users, manually created dashboards)."
  type        = string
  default     = "10Gi"
}

###############################################################################
# Alerting
###############################################################################

variable "enable_default_rules" {
  description = "Keep the ~150 community alert/recording rules shipped with kube-prometheus-stack, in addition to this module's node & pod health rules."
  type        = bool
  default     = true
}

variable "additional_rule_files" {
  description = "Paths to extra Prometheus rule files (standard `groups:` format) to load."
  type        = list(string)
  default     = []
}

variable "slack_webhook_url" {
  description = "Slack incoming-webhook URL for all alerts. Null disables Slack."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.slack_webhook_url == null || can(regex("^https://hooks\\.slack\\.com/", coalesce(var.slack_webhook_url, "https://hooks.slack.com/")))
    error_message = "slack_webhook_url must be a https://hooks.slack.com/... URL."
  }
}

variable "slack_channel" {
  description = "Slack channel for alerts."
  type        = string
  default     = "#alerts"
}

variable "pagerduty_routing_key" {
  description = "PagerDuty Events API v2 routing key. Only CRITICAL alerts are sent to PagerDuty. Null disables it."
  type        = string
  default     = null
  sensitive   = true
}

###############################################################################
# Dashboards & access
###############################################################################

variable "additional_dashboard_files" {
  description = "Paths to extra Grafana dashboard JSON files to provision."
  type        = list(string)
  default     = []
}

variable "grafana_ingress" {
  description = "Expose Grafana through an Ingress. Disabled by default: use the port-forward command from the outputs."
  type = object({
    enabled         = bool
    host            = optional(string, "")
    class_name      = optional(string, "")
    tls_secret_name = optional(string, "")
    annotations     = optional(map(string), {})
  })
  default = { enabled = false }

  validation {
    condition     = !var.grafana_ingress.enabled || length(var.grafana_ingress.host) > 0
    error_message = "grafana_ingress.host is required when the ingress is enabled."
  }
}

variable "extra_values" {
  description = "Extra kube-prometheus-stack values (YAML), applied last so they override everything else."
  type        = string
  default     = ""
}
