# One log group per student. Kept as separate log groups (not separate
# streams within one shared group) so IAM policies in modules/tenant_app can
# scope each task's logs:PutLogEvents/CreateLogStream permission to exactly
# one ARN -- isolation applies to log visibility too, not just network
# traffic.
resource "aws_cloudwatch_log_group" "tenant" {
  for_each = var.students

  name              = "/ecs/${var.project_name}/${each.value.sanitized_id}"
  retention_in_days = var.log_retention_days

  tags = {
    Owner = each.value.sanitized_id
  }
}

resource "aws_cloudwatch_log_group" "cache" {
  name              = "/ecs/${var.project_name}/cache"
  retention_in_days = var.log_retention_days
}
