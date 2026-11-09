variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
}

variable "location" {
  description = "Region or zone of the cluster."
  type        = string
}

variable "cluster_name" {
  description = "Name of the existing GKE cluster."
  type        = string
}

variable "autopilot" {
  description = "true for GKE Autopilot clusters."
  type        = bool
  default     = false
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook for alerts (optional)."
  type        = string
  default     = null
  sensitive   = true
}
