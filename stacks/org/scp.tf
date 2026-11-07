# SCPs don't apply to the management account, so these only limit the two
# member accounts. AWS's default FullAWSAccess stays attached, and these only
# take rights away.

locals {
  sso_role_arn     = "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*"
  infra_ci_roles   = "arn:aws:iam::*:role/v1be-infra-*"
  third_party_arns = "arn:aws:ssm:*:*:parameter/*/third-party/*"

  # ADR-0007: only these services work in a member account. An episode that needs
  # another one adds it here during Setup, then the user runs this stack.
  shared_services = [
    "acm",
    "apigateway",
    "budgets",
    "ce",
    "cloudfront",
    "cloudfront-keyvaluestore",
    "cloudtrail",
    "cloudwatch",
    "dsql",
    "dynamodb",
    "execute-api",
    "health",
    "iam",
    "kms",
    "lambda",
    "logs",
    "s3",
    "sns",
    "ssm",
    "sts",
    "support",
    "tag",
  ]

  allowed_services = {
    portfolio = local.shared_services
    cafe      = concat(local.shared_services, ["backup", "backup-storage"])
  }
}

# A deny on everything else leaves FullAWSAccess in place, so a mistake in this
# list can't remove access to the services that are on it.
data "aws_iam_policy_document" "allowed_services" {
  for_each = local.allowed_services

  statement {
    sid         = "DenyUnlistedServices"
    effect      = "Deny"
    not_actions = [for service in each.value : "${service}:*"]
    resources   = ["*"]
  }

  # Everything stays in Singapore. These exemptions follow AWS's sample Region SCP,
  # limited to services on the allowlists: they're global, or CloudFront needs them
  # in us-east-1. CloudWatch reads are exempt for CloudFront's metrics.
  statement {
    sid    = "DenyOtherRegions"
    effect = "Deny"
    not_actions = [
      "acm:*",
      "budgets:*",
      "ce:*",
      "cloudfront-keyvaluestore:*",
      "cloudfront:*",
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
      "health:*",
      "iam:*",
      "kms:*",
      "s3:GetAccountPublic*",
      "s3:ListAllMyBuckets",
      "s3:PutAccountPublic*",
      "sts:*",
      "support:*",
    ]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = ["ap-southeast-1"]
    }
  }

  # People sign in with Identity Center and CI with OIDC, so nothing needs an IAM
  # user or a long-lived key. Blocking them removes a common way to keep access
  # after a breach.
  statement {
    sid       = "DenyLongLivedCredentials"
    effect    = "Deny"
    actions   = ["iam:CreateAccessKey", "iam:CreateUser"]
    resources = ["*"]
  }
}

# for_each below uses locals only, because terraform import reads this file before
# any resources are planned, and a value taken from a resource isn't known yet.

# ADR-0009: Terraform never needs third-party keys, so people's sessions and
# v1be-infra's CI roles can't read them. Lambdas and episode roles still can.
data "aws_iam_policy_document" "third_party_keys" {
  statement {
    sid       = "DenyReadingThirdPartyKeys"
    effect    = "Deny"
    actions   = ["ssm:GetParameter*"]
    resources = [local.third_party_arns]

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = [local.sso_role_arn, local.infra_ci_roles]
    }
  }

  # A path search is checked against the path asked for, not what comes back,
  # so a deny on the keys alone wouldn't stop a search of a parent path.
  statement {
    sid       = "DenySearchingByPath"
    effect    = "Deny"
    actions   = ["ssm:GetParametersByPath"]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = [local.sso_role_arn, local.infra_ci_roles]
    }
  }
}

resource "aws_organizations_policy" "allowed_services" {
  for_each = local.allowed_services

  name        = "v1be-allowed-services-${each.key}"
  description = "Denies unlisted services, other Regions, and IAM users and access keys."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.allowed_services[each.key].json

  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy" "third_party_keys" {
  name        = "v1be-third-party-keys"
  description = "Stops Identity Center and v1be-infra CI reading third-party keys in SSM."
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.third_party_keys.json

  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_policy_attachment" "allowed_services" {
  for_each = local.allowed_services

  policy_id = aws_organizations_policy.allowed_services[each.key].id
  target_id = aws_organizations_account.member[each.key].id
}

resource "aws_organizations_policy_attachment" "third_party_keys" {
  for_each = local.member_accounts

  policy_id = aws_organizations_policy.third_party_keys.id
  target_id = aws_organizations_account.member[each.key].id
}
