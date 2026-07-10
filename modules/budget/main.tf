# Account-wide budget rather than a tag-scoped one on purpose: AWS Budgets
# can filter by cost-allocation tag, but user-defined tags (like our
# Project tag) must first be *activated* for cost allocation from the
# Billing console -- a manual, one-time, console-only step that would
# contradict "no direct console access" and "must execute flawlessly on
# the first run." Given this is expected to be a dedicated sandbox account
# for the assessment, an account-wide cap is functionally equivalent and
# doesn't depend on a step we cannot automate. See docs/DECISIONS.md.
resource "aws_budgets_budget" "hard_cap" {
  name         = "${var.project_name}-hard-cap"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = length(var.budget_alert_emails) > 0 ? [
      { threshold = 80, type = "ACTUAL" },
      { threshold = 100, type = "ACTUAL" },
      { threshold = 100, type = "FORECASTED" },
    ] : []

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = var.budget_alert_emails
    }
  }
}
