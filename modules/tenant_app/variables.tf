variable "project_name" {
  type = string
}

variable "aws_region" {
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

variable "cluster_id" {
  type = string
}

variable "tenant_subnet_ids" {
  type = map(string)
}

variable "tenant_security_group_ids" {
  type = map(string)
}

variable "repository_urls" {
  type = map(string)
}

variable "repository_arns" {
  type = map(string)
}

variable "tenant_log_group_names" {
  type = map(string)
}

variable "tenant_log_group_arns" {
  type = map(string)
}

variable "image_tag" {
  type = string
}

variable "app_port" {
  type = number
}

variable "cache_host" {
  type = string
}

variable "cache_port" {
  type = number
}

variable "container_cpu" {
  type = number
}

variable "container_memory" {
  type = number
}
