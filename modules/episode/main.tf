# One episode's CI role and permissions boundary, in one account (ADR-0011).
# Later template slices add the services they need here.

locals {
  prefix             = "v1be-${var.name}"
  ci_role_name       = "${local.prefix}-ci"
  boundary_name      = "${local.prefix}-boundary"
  boundary_arn       = "arn:aws:iam::${var.account_id}:policy/${local.boundary_name}"
  state_bucket       = "arn:aws:s3:::v1be-${var.account}-state"
  role_arns          = "arn:aws:iam::${var.account_id}:role/${local.prefix}-*"
  ssm_path           = "arn:aws:ssm:ap-southeast-1:${var.account_id}:parameter/${var.name}/*"
  functions          = "arn:aws:lambda:ap-southeast-1:${var.account_id}:function:${local.prefix}-*"
  log_groups         = "arn:aws:logs:ap-southeast-1:${var.account_id}:log-group:/aws/lambda/${local.prefix}-*"
  apis               = "arn:aws:apigateway:ap-southeast-1::/apis"
  site_bucket_prefix = "${local.prefix}-site"
  site_bucket        = "${local.site_bucket_prefix}-${var.account}"
  api_name           = "${local.prefix}-api"
  clusters           = "arn:aws:dsql:ap-southeast-1:${var.account_id}:cluster/*"
  tables             = "arn:aws:dynamodb:ap-southeast-1:${var.account_id}:table/${local.prefix}-*"
  alarms             = "arn:aws:cloudwatch:ap-southeast-1:${var.account_id}:alarm:${local.prefix}-*"

  # The accounts stack owns this topic, and it emails the owner (Q61).
  alerts_topic = "arn:aws:sns:ap-southeast-1:${var.account_id}:v1be-alerts"

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

  # The Lambda's database role. dsql:DbConnectAdmin stays out, so no role CI
  # makes can hold admin rights on a cluster (ADR-0003).
  statement {
    sid       = "ConnectToOwnClusters"
    actions   = ["dsql:DbConnect"]
    resources = [local.clusters]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/episode"
      values   = [var.name]
    }
  }

  # The rate-limit and spend-cap counters (Q56). Items only, never the table.
  statement {
    sid = "CountInOwnTables"
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [local.tables]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = local.boundary_name
  description = "The most any role made by ${var.name}'s CI can do."
  policy      = data.aws_iam_policy_document.boundary.json
}

data "aws_iam_policy_document" "ci" {
  source_policy_documents = data.aws_iam_policy_document.branch[*].json

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

  # Each target's counter table (Q56). The names keep CI off other episodes'.
  statement {
    sid       = "ManageOwnTables"
    actions   = ["dynamodb:*"]
    resources = [local.tables]
  }

  statement {
    sid       = "ListTables"
    actions   = ["dynamodb:ListTables"]
    resources = ["*"]
  }

  # Production's alarms (Q61). Their actions may only email through the
  # accounts stack's topic. The Null check stops an alarm with no actions slipping
  # past ForAllValues, which is true for an empty list.
  statement {
    sid       = "CreateAlarmsThatEmail"
    actions   = ["cloudwatch:PutMetricAlarm"]
    resources = [local.alarms]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "cloudwatch:AlarmActions"
      values   = [local.alerts_topic]
    }

    condition {
      test     = "Null"
      variable = "cloudwatch:AlarmActions"
      values   = ["false"]
    }
  }

  statement {
    sid = "TidyOwnAlarms"
    actions = [
      "cloudwatch:DeleteAlarms",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = [local.alarms]
  }

  statement {
    sid       = "ReadAlarms"
    actions   = ["cloudwatch:DescribeAlarms"]
    resources = ["*"]
  }

  # A new API must carry the episode's tag, because API IDs can't be named ahead.
  # Tags go in the create call. The /tags/* resource has no condition keys, so a
  # right on it here would let CI re-tag another episode's API (ADR-0011).
  statement {
    sid       = "CreateTaggedApis"
    actions   = ["apigateway:POST"]
    resources = [local.apis]

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

  # AWS makes this role when an account's first cluster is created, and the
  # caller needs the right to trigger it.
  statement {
    sid       = "AllowDsqlServiceRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["dsql.amazonaws.com"]
    }
  }

  # A new cluster must carry the episode's tag, because cluster IDs can't be
  # named ahead.
  statement {
    sid       = "CreateTaggedClusters"
    actions   = ["dsql:CreateCluster", "dsql:TagResource"]
    resources = [local.clusters]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/episode"
      values   = [var.name]
    }

    # IfExists because a new cluster has no tags yet. Without this, CI could tag
    # another episode's cluster as its own and take it over.
    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:ResourceTag/episode"
      values   = [var.name]
    }
  }

  # dsql:UpdateCluster is left out on purpose. It's the only way to turn off
  # deletion protection, so a run can't delete a production cluster.
  statement {
    sid = "ManageOwnClusters"
    actions = [
      "dsql:DbConnectAdmin",
      "dsql:DeleteCluster",
      "dsql:GetCluster",
      "dsql:GetVpcEndpointServiceName",
      "dsql:ListTagsForResource",
      "dsql:TagResource",
      "dsql:UntagResource",
    ]
    resources = [local.clusters]

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
