data "aws_ssoadmin_instances" "this" {}

data "aws_identitystore_user" "admin" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = "v1be-admin"
    }
  }
}

locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

# Made by hand in phase A, so the first run imports it. The assignment that lets
# v1be-admin into the management account stays out of Terraform on purpose: no
# mistake in this stack can remove the login that's needed to fix it.
resource "aws_ssoadmin_permission_set" "admin" {
  name         = "AdministratorAccess"
  instance_arn = local.instance_arn

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_account_assignment" "admin" {
  for_each = local.member_accounts

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  principal_id       = data.aws_identitystore_user.admin.user_id
  principal_type     = "USER"
  target_id          = aws_organizations_account.member[each.key].id
  target_type        = "AWS_ACCOUNT"

  depends_on = [aws_ssoadmin_managed_policy_attachment.admin]
}
