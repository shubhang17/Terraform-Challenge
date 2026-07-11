# Budget named per sandbox rules (cybered-candidate-003-*). Alerts route to
# the pre-created SNS topic at 50/80/100% — budgets are not a hard stop,
# so tear down promptly when finished (terraform destroy).
resource "aws_budgets_budget" "hard_cap" {
  name         = "${var.project_name}-hard-cap"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = var.budget_sns_topic_arn != "" ? [
      { threshold = 50, type = "ACTUAL" },
      { threshold = 80, type = "ACTUAL" },
      { threshold = 100, type = "ACTUAL" },
      { threshold = 100, type = "FORECASTED" },
    ] : []

    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value.threshold
      threshold_type            = "PERCENTAGE"
      notification_type         = notification.value.type
      subscriber_sns_topic_arns = [var.budget_sns_topic_arn]
    }
  }
}
