output "repository_urls" {
  description = "Map of resource_key -> ECR repository URL, one per student."
  value       = { for k, r in aws_ecr_repository.student : k => r.repository_url }
}

output "repository_arns" {
  description = "Map of resource_key -> ECR repository ARN, used to scope IAM policies to a single tenant repo."
  value       = { for k, r in aws_ecr_repository.student : k => r.arn }
}

output "push_dependency" {
  description = "Exposed so tenant_app services can depend_on the image actually existing in ECR before scheduling tasks."
  value       = [for r in null_resource.push_image : r.id]
}
