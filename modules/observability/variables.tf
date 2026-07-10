variable "project_name" {
  type = string
}

variable "students" {
  type = map(object({
    index        = number
    raw          = string
    sanitized_id = string
    resource_key = string
  }))
}

variable "log_retention_days" {
  type = number
}
