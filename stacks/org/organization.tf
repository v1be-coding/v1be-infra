locals {
  mailbox = split("@", var.root_email)

  member_accounts = {
    portfolio = {
      name = "portfolio"
      tag  = "portfolio"
    }
    cafe = {
      name = "collective-cafe-prod"
      tag  = "cafe"
    }
  }
}

# Identity Center created this Organization, so the first run imports it.
resource "aws_organizations_organization" "this" {
  feature_set                   = "ALL"
  aws_service_access_principals = ["sso.amazonaws.com"]
  enabled_policy_types          = ["SERVICE_CONTROL_POLICY"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_organizations_account" "member" {
  for_each = local.member_accounts

  name      = each.value.name
  email     = "${local.mailbox[0]}+${each.value.tag}@${local.mailbox[1]}"
  parent_id = aws_organizations_organization.this.roots[0].id

  # Closing an account is a decision for a person, not a side effect of a run.
  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
  }
}
