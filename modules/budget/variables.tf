variable "project_name" {
  type = string
}

variable "budget_limit_usd" {
  type = number
}

variable "budget_sns_topic_arn" {
  description = "Pre-created SNS topic for budget alert notifications."
  type        = string
}
