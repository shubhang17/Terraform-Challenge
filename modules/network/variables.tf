variable "project_name" {
  type = string
}

variable "students" {
  description = "Sanitized student records, keyed by their unique resource_key. See root locals.tf."
  type = map(object({
    index        = number
    raw          = string
    sanitized_id = string
    resource_key = string
  }))
}

variable "vpc_cidr" {
  type = string
}

variable "app_port" {
  type = number
}

variable "cache_port" {
  type = number
}
