variable "aws_region" {
  description = "AWS region — must be ap-south-1 per the candidate environment sheet."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Required resource prefix for every resource this configuration creates."
  type        = string
  default     = "cybered-candidate-003"
}

variable "students" {
  description = <<-EOT
    Raw student identifiers as they arrive from the roster system. These are
    NOT assumed to be safe resource names — they are sanitized in locals.tf
    before being used anywhere (e.g. "Alice Smith!" -> "alice-smith").
  EOT
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block for the shared lab VPC. Each student receives a /24 carved out of this block."
  type        = string
  default     = "10.42.0.0/16"
}

variable "app_port" {
  description = "Port the per-student application container listens on (ttyd default)."
  type        = number
  default     = 7681
}

variable "cache_port" {
  description = "Port the centralized cache service listens on. Injected into every app container as CACHE_PORT."
  type        = number
  default     = 6379
}

variable "app_container_cpu" {
  description = "Fargate vCPU units (1024 = 1 vCPU) for each student's application task."
  type        = number
  default     = 256
}

variable "app_container_memory" {
  description = "Fargate memory (MiB) for each student's application task."
  type        = number
  default     = 512
}

variable "cache_container_cpu" {
  description = "Fargate vCPU units for the shared cache task."
  type        = number
  default     = 256
}

variable "cache_container_memory" {
  description = "Fargate memory (MiB) for the shared cache task."
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch log retention window, in days. Constrained to 3-7 to avoid storage leakage."
  type        = number
  default     = 5

  validation {
    condition     = var.log_retention_days >= 3 && var.log_retention_days <= 7
    error_message = "log_retention_days must be between 3 and 7 (inclusive) per the retention guardrail."
  }
}

variable "budget_limit_usd" {
  description = "Hard monthly cost cap enforced by the AWS Budget resource."
  type        = number
  default     = 50
}

variable "budget_sns_topic_arn" {
  description = "Pre-created SNS topic for budget alerts (reference only — do not modify the topic itself)."
  type        = string
  default     = "arn:aws:sns:ap-south-1:150105760360:cybered-assessment-budget-alerts"
}

variable "allowed_ingress_cidr" {
  description = "CIDR allowed to reach student terminals on app_port (your public IP as x.x.x.x/32)."
  type        = string
}

variable "iam_role_path" {
  description = "Required IAM path for every role created in the sandbox."
  type        = string
  default     = "/cybered-assessment/candidate-003/"
}

variable "iam_permissions_boundary_arn" {
  description = "Permissions boundary that must be attached to every IAM role created."
  type        = string
  default     = "arn:aws:iam::150105760360:policy/CyberEdAssessmentBoundary-candidate-003"
}

variable "app_source_path" {
  description = "Path to the mock application build context (Dockerfile + entrypoint) that gets built and promoted into each student's private ECR repository."
  type        = string
  default     = "./app"
}

variable "image_tag" {
  description = "Tag applied to the built application image before it is pushed into each student's ECR repository."
  type        = string
  default     = "latest"
}
