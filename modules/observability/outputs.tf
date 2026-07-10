output "tenant_log_group_names" {
  value = { for k, g in aws_cloudwatch_log_group.tenant : k => g.name }
}

output "tenant_log_group_arns" {
  value = { for k, g in aws_cloudwatch_log_group.tenant : k => g.arn }
}

output "cache_log_group_name" {
  value = aws_cloudwatch_log_group.cache.name
}

output "cache_log_group_arn" {
  value = aws_cloudwatch_log_group.cache.arn
}
