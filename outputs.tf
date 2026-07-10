output "student_ids" {
  description = "Sanitized student identifiers actually used for resource naming/tagging."
  value       = { for k, s in local.students : k => s.sanitized_id }
}

output "ecr_repository_urls" {
  value = module.registry.repository_urls
}

output "tenant_log_groups" {
  value = module.observability.tenant_log_group_names
}

output "cache_log_group" {
  value = module.observability.cache_log_group_name
}

output "cache_host" {
  value = module.cache.cache_host
}

output "budget_name" {
  value = module.budget.budget_name
}

output "ttyd_credentials" {
  description = "Per-student ttyd basic-auth credentials. Sensitive -- see docs/RUNBOOK.md for how to retrieve them safely."
  value       = module.tenant_app.ttyd_credentials
  sensitive   = true
}
