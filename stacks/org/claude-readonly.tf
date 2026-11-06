# What Claude uses to look around AWS (ADR-0012). It's assigned to the member
# accounts only, so it has no way into the management account.
resource "aws_identitystore_user" "claude_readonly" {
  identity_store_id = local.identity_store_id
  user_name         = "claude-readonly"
  display_name      = "Claude read-only"

  name {
    given_name  = "Claude"
    family_name = "Read-only"
  }

  emails {
    primary = true
    type    = "work"
    value   = "${local.mailbox[0]}+claude-readonly@${local.mailbox[1]}"
  }
}

resource "aws_ssoadmin_permission_set" "claude_readonly" {
  name             = "ClaudeReadOnly"
  description      = "View resources in member accounts and read portfolio Lambda logs. No secrets or state."
  instance_arn     = local.instance_arn
  session_duration = "PT8H"
}

# ViewOnlyAccess, not ReadOnlyAccess: the wider policy can read S3 objects and
# SSM values, and state holds the origin header and generated secrets.
resource "aws_ssoadmin_managed_policy_attachment" "claude_readonly" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.claude_readonly.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

data "aws_iam_policy_document" "claude_readonly" {
  statement {
    sid = "ReadPortfolioLambdaLogs"
    actions = [
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
      "logs:GetLogEvents",
    ]
    resources = [
      "arn:aws:logs:*:${aws_organizations_account.member["portfolio"].id}:log-group:/aws/lambda/v1be-*",
      "arn:aws:logs:*:${aws_organizations_account.member["portfolio"].id}:log-group:/aws/lambda/v1be-*:*",
    ]
  }

  statement {
    sid    = "DenySecretValues"
    effect = "Deny"
    actions = [
      "kms:Decrypt",
      "secretsmanager:GetSecretValue",
      "ssm:GetParameter*",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyStateBuckets"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::v1be-*state*", "arn:aws:s3:::v1be-*state*/*"]
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "claude_readonly" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.claude_readonly.arn
  inline_policy      = data.aws_iam_policy_document.claude_readonly.json
}

resource "aws_ssoadmin_account_assignment" "claude_readonly" {
  for_each = local.member_accounts

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.claude_readonly.arn
  principal_id       = aws_identitystore_user.claude_readonly.user_id
  principal_type     = "USER"
  target_id          = aws_organizations_account.member[each.key].id
  target_type        = "AWS_ACCOUNT"

  depends_on = [
    aws_ssoadmin_managed_policy_attachment.claude_readonly,
    aws_ssoadmin_permission_set_inline_policy.claude_readonly,
  ]
}
