locals {
  is_portfolio = var.account == "portfolio"

  # GitHub's public numeric IDs. Repos made after July 15, 2026 put them in `sub`,
  # and they survive a rename, so a new repo can't take over this trust (ADR-0011).
  github_owner_id = 352848052
  infra_repo_id   = 1447858505
  infra_repo_sub  = "repo:v1be-coding@${local.github_owner_id}/v1be-infra@${local.infra_repo_id}"

  environments = toset(["plan", "apply"])

  # The state only lives in portfolio, so the café's roles never touch it.
  infra_state_arn = "arn:aws:s3:::v1be-infra-state"
}

# GitHub is one of the providers IAM verifies itself, so no thumbprint is needed.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Only a job in that exact protected environment gets in, and GitHub only lets
# main use those environments. A branch's token names the branch, so it's refused.
data "aws_iam_policy_document" "trust" {
  for_each = local.environments

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.infra_repo_sub}:environment:${each.key}"]
    }
  }
}

# The name must start v1be-infra-, because the third-party key SCP matches it.
resource "aws_iam_role" "ci" {
  for_each = local.environments

  name               = "v1be-infra-${each.key}"
  description        = "v1be-infra CI, ${each.key} environment only."
  assume_role_policy = data.aws_iam_policy_document.trust[each.key].json
}

# Both roles refresh edge and episodes, so both need to read what those stacks
# manage. The SCP still blocks third-party keys.
resource "aws_iam_role_policy_attachment" "read_only" {
  for_each = local.environments

  role       = aws_iam_role.ci[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan" {
  statement {
    sid = "ReadKeyValueStores"
    actions = [
      "cloudfront-keyvaluestore:DescribeKeyValueStore",
      "cloudfront-keyvaluestore:GetKey",
      "cloudfront-keyvaluestore:ListKeys",
    ]
    resources = ["*"]
  }

  # A plan changes nothing, but S3 locking still has to write its lock file.
  dynamic "statement" {
    for_each = local.is_portfolio ? [1] : []

    content {
      sid       = "LockInfraState"
      actions   = ["s3:DeleteObject", "s3:PutObject"]
      resources = ["${local.infra_state_arn}/*.tflock"]
    }
  }
}

data "aws_iam_policy_document" "apply" {
  statement {
    sid = "ManageEdgeAndCertificates"
    actions = [
      "acm:*",
      "cloudfront-keyvaluestore:*",
      "cloudfront:*",
    ]
    resources = ["*"]
  }

  # Only generated secrets. People enter third-party keys through a wizard.
  statement {
    sid = "ManageGeneratedSecrets"
    actions = [
      "ssm:AddTagsToResource",
      "ssm:DeleteParameter",
      "ssm:PutParameter",
      "ssm:RemoveTagsFromResource",
    ]
    resources = ["arn:aws:ssm:ap-southeast-1:${var.account_id}:parameter/*/internal/*"]
  }

  # Each episode's production edge: its site bucket, and its API shell, which
  # the template fills in (ADR-0010).
  statement {
    sid       = "ManageEpisodeSites"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::v1be-*-site-*", "arn:aws:s3:::v1be-*-site-*/*"]
  }

  statement {
    sid       = "ManageEpisodeApis"
    actions   = ["apigateway:*"]
    resources = ["arn:aws:apigateway:ap-southeast-1::/apis", "arn:aws:apigateway:ap-southeast-1::/apis/*", "arn:aws:apigateway:ap-southeast-1::/tags/*"]
  }

  # episodes makes each episode's CI role and boundary.
  statement {
    sid = "ManageEpisodeRoles"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:CreateRole",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:TagRole",
      "iam:UntagPolicy",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
    ]
    resources = [
      "arn:aws:iam::${var.account_id}:policy/v1be-*",
      "arn:aws:iam::${var.account_id}:role/v1be-*",
    ]
  }

  # CI can't widen its own access or the trust it signs in with. Those change
  # only through this stack, in the Sandbox (ADR-0012).
  statement {
    sid    = "KeepOutOfThisStack"
    effect = "Deny"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:SetDefaultPolicyVersion",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
    ]
    resources = ["arn:aws:iam::${var.account_id}:role/v1be-infra-*"]
  }

  dynamic "statement" {
    for_each = local.is_portfolio ? [1] : []

    content {
      sid       = "WriteInfraState"
      actions   = ["s3:DeleteObject", "s3:PutObject"]
      resources = ["${local.infra_state_arn}/*"]
    }
  }

  # ADR-0007: the action that stops deploys is only on portfolio.
  dynamic "statement" {
    for_each = local.is_portfolio ? [1] : []

    content {
      sid       = "ManageBudgetsAction"
      actions   = ["budgets:*"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = local.is_portfolio ? [1] : []

    content {
      sid       = "PassBudgetsActionRole"
      actions   = ["iam:PassRole"]
      resources = ["arn:aws:iam::${var.account_id}:role/v1be-*"]

      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["budgets.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "v1be-infra-plan"
  role   = aws_iam_role.ci["plan"].id
  policy = data.aws_iam_policy_document.plan.json
}

resource "aws_iam_role_policy" "apply" {
  name   = "v1be-infra-apply"
  role   = aws_iam_role.ci["apply"].id
  policy = data.aws_iam_policy_document.apply.json
}
