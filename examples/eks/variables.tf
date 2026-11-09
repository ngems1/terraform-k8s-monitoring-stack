variable "region" {
  description = "AWS region of the cluster."
  type        = string
}

variable "cluster_name" {
  description = "Name of the existing EKS cluster."
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook for alerts (optional)."
  type        = string
  default     = null
  sensitive   = true
}
