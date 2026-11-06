# ADR-0007: covers all three accounts, because the management account's budget
# includes its member accounts. It only alerts, and the Budgets action that
# stops deploys comes with the episodes stack.
resource "aws_budgets_budget" "organization" {
  name         = "v1be-organization-monthly"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 3
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.root_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 5
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.root_email]
  }
}
