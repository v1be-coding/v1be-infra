# One episode's CI role and permissions boundary, in one account (ADR-0011).
# Later template slices add the services they need here.

locals {
  prefix        = "v1be-${var.name}"
  ci_role_name  = "${local.prefix}-ci"
  boundary_name = "${local.prefix}-boundary"
  boundary_arn  = "arn:aws:iam::${var.account_id}:policy/${local.boundary_name}"
  state_bucket  = "arn:aws:s3:::v1be-${var.account}-state"
  role_arns     = "arn:aws:iam::${var.account_id}:role/${local.prefix}-*"
  ssm_path      = "arn:aws:ssm:ap-southeast-1:${var.account_id}:parameter/${var.name}/*"
  functions     = "arn:aws:lambda:ap-southeast-1:${var.account_id}:function:${local.prefix}-*"
  log_groups    = "arn:aws:logs:ap-southeast-1:${var.account_id}:log-group:/aws/lambda/${local.prefix}-*"
  apis          = "arn:aws:apigateway:ap-southeast-1::/apis"
  site_bucket   = "${local.prefix}-site-${var.account}"
  api_name      = "${local.prefix}-api"

  # Portfolio: branch environments through a PR, and main for production and
  # schedules. Café: only GitHub's approved production environment (ADR-0005).
  subjects = var.account == "cafe" ? [
    "${var.repo_sub}:environment:production",
    ] : [
    "${var.repo_sub}:pull_request",
    "${var.repo_sub}:ref:refs/heads/main",
  ]
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.subjects
    }
  }
}

# The ceiling for every role CI creates, so none can do more than an episode's
# Lambda needs, or reach another episode's keys.
data "aws_iam_policy_document" "boundary" {
  statement {
    sid = "WriteOwnLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [local.log_groups, "${local.log_groups}:*"]
  }

  statement {
    sid = "ReadOwnSecrets"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [local.ssm_path]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = local.boundary_name
  description = "The most any role made by ${var.name}'s CI can do."
  policy      = data.aws_iam_policy_document.boundary.json
}

data "aws_iam_policy_document" "ci" {
  statement {
    sid       = "ListOwnState"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.name}/*"]
    }
  }

  statement {
    sid       = "UseOwnState"
    actions   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = ["${local.state_bucket}/${var.name}/*"]
  }

  statement {
    sid = "ReadOwnSecrets"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [local.ssm_path]
  }


  # Deploying the site is all a run does at the edge (ADR-0010).
  statement {
    sid       = "ListOwnSite"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.site_bucket}"]
  }

  statement {
    sid       = "DeployOwnSite"
    actions   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::${local.site_bucket}/*"]
  }

  statement {
    sid       = "ClearOwnCache"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }

  statement {
    sid       = "FindDistributions"
    actions   = ["cloudfront:ListDistributions"]
    resources = ["*"]
  }
  statement {
    sid       = "ManageOwnFunctions"
    actions   = ["lambda:*"]
    resources = [local.functions]
  }

  statement {
    sid       = "ManageOwnLogs"
    actions   = ["logs:*"]
    resources = [local.log_groups, "${local.log_groups}:*"]
  }

  statement {
    sid       = "ListLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  # A new API must carry the episode's tag, because API IDs can't be named ahead.
  statement {
    sid       = "CreateTaggedApis"
    actions   = ["apigateway:POST", "apigateway:TagResource"]
    resources = [local.apis, "arn:aws:apigateway:ap-southeast-1::/tags/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/episode"
      values   = [var.name]
    }
  }

  statement {
    sid       = "ReadApis"
    actions   = ["apigateway:GET"]
    resources = [local.apis, "${local.apis}/*", "arn:aws:apigateway:ap-southeast-1::/tags/*"]
  }

  statement {
    sid = "ManageOwnApis"
    actions = [
      "apigateway:DELETE",
      "apigateway:PATCH",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:TagResource",
      "apigateway:UntagResource",
    ]
    resources = ["${local.apis}/*", "arn:aws:apigateway:ap-southeast-1::/tags/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/episode"
      values   = [var.name]
    }
  }

  statement {
    sid = "ReadOwnRoles"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRolePolicies",
      "iam:ListRoleTags",
    ]
    resources = [local.role_arns]
  }

  # Every role CI makes carries the boundary, or this denies it.
  statement {
    sid = "ManageBoundedRoles"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
    ]
    resources = [local.role_arns]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.boundary_arn]
    }
  }

  statement {
    sid = "TidyOwnRoles"
    actions = [
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
    ]
    resources = [local.role_arns]
  }

  statement {
    sid       = "PassRolesToLambda"
    actions   = ["iam:PassRole"]
    resources = [local.role_arns]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  # The wildcard above would match this role and its boundary, so keep CI off them.
  statement {
    sid    = "KeepOffOwnLimits"
    effect = "Deny"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:DeleteRole",
      "iam:DeleteRolePermissionsBoundary",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:PutRolePolicy",
      "iam:SetDefaultPolicyVersion",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
    ]
    resources = [
      "arn:aws:iam::${var.account_id}:role/${local.ci_role_name}",
      local.boundary_arn,
    ]
  }

  statement {
    sid    = "KeepBoundariesOn"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "NoAccountWideChanges"
    effect = "Deny"
    actions = [
      "account:*",
      "budgets:*",
      "organizations:*",
      "ssm:DeleteParameter",
      "ssm:DeleteParameters",
      "ssm:PutParameter",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "NoInfraState"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::v1be-infra-state", "arn:aws:s3:::v1be-infra-state/*"]
  }
}

# Not managed_policy_arns: the Budgets action attaches a policy to this role, and
# Terraform would remove it (ADR-0011).
resource "aws_iam_role" "ci" {
  name               = local.ci_role_name
  description        = "CI for the ${var.name} episode."
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy" "ci" {
  name   = local.ci_role_name
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci.json
}
