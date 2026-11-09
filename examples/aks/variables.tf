variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the AKS cluster."
  type        = string
}

variable "cluster_name" {
  description = "Name of the existing AKS cluster."
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook for alerts (optional)."
  type        = string
  default     = null
  sensitive   = true
}
