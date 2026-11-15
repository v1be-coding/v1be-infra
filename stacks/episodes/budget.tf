# ADR-0007's backstop: when portfolio's spending for the month passes the limit,
# Budgets attaches AWS's deny-all policy to every portfolio episode's CI role, so
# deploys stop. Anything already running keeps costing money. docs/runbook.md
# says how to lift it: reverse, then reset, and never detach it by hand.
#
# Only portfolio has one. Café backups are caught by the org budget's alerts, in
# the org stack.
#
# With no episodes there are no CI roles, and Budgets needs at least one target,
# so the action and its rights exist only while an episode does. The budget and
# its role stay either way.

locals {
  budget_limit_usd = "5"
  deny_all_arn     = "arn:aws:iam::aws:policy/AWSDenyAll"
  ci_role_names    = [for target in module.portfolio : target.ci_role_name]
  has_ci_roles     = length(local.ci_role_names) > 0

  # The accounts stack owns this topic, and it emails the owner (Q61).
  alerts_topic_arn = "arn:aws:sns:ap-southeast-1:${var.portfolio_account_id}:v1be-alerts"
}

resource "aws_budgets_budget" "portfolio" {
  provider = aws.portfolio

  name         = "v1be-portfolio-monthly"
  budget_type  = "COST"
  limit_amount = local.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
}

data "aws_iam_policy_document" "budgets_action_trust" {
  provider = aws.portfolio

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.portfolio_account_id]
    }
  }
}

resource "aws_iam_role" "budgets_action" {
  provider = aws.portfolio

  name               = "v1be-budgets-action"
  description        = "Lets Budgets attach and lift deny-all on portfolio's episode CI roles."
  assume_role_policy = data.aws_iam_policy_document.budgets_action_trust.json
}

# Only deny-all, and only on the episodes' CI roles.
data "aws_iam_policy_document" "budgets_action" {
  count    = local.has_ci_roles ? 1 : 0
  provider = aws.portfolio

  statement {
    actions   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = [for name in local.ci_role_names : "arn:aws:iam::${var.portfolio_account_id}:role/${name}"]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = [local.deny_all_arn]
    }
  }
}

resource "aws_iam_role_policy" "budgets_action" {
  count    = local.has_ci_roles ? 1 : 0
  provider = aws.portfolio

  name   = "v1be-budgets-action"
  role   = aws_iam_role.budgets_action.id
  policy = data.aws_iam_policy_document.budgets_action[0].json
}

moved {
  from = aws_iam_role_policy.budgets_action
  to   = aws_iam_role_policy.budgets_action[0]
}

resource "aws_budgets_budget_action" "portfolio" {
  count    = local.has_ci_roles ? 1 : 0
  provider = aws.portfolio

  budget_name        = aws_budgets_budget.portfolio.name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budgets_action.arn

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 100
  }

  definition {
    iam_action_definition {
      policy_arn = local.deny_all_arn
      roles      = local.ci_role_names
    }
  }

  subscriber {
    address           = local.alerts_topic_arn
    subscription_type = "SNS"
  }

  # The role's rights must exist before Budgets checks them.
  depends_on = [aws_iam_role_policy.budgets_action]
}

moved {
  from = aws_budgets_budget_action.portfolio
  to   = aws_budgets_budget_action.portfolio[0]
}
