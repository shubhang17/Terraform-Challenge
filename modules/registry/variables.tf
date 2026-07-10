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

variable "app_source_path" {
  description = "Absolute (or apply-time-cwd-relative) path to the Docker build context."
  type        = string
}

variable "image_tag" {
  type = string
}
