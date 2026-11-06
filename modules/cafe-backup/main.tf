# ADR-0005: DSQL has no point-in-time recovery, so real café data gets a weekly
# snapshot, kept 14 days. DSQL backups are full copies, so we keep only a few.

# The map must list every resource type. AWS always returns all of them, so a
# shorter map would show as a change on every plan. A type AWS adds later will
# show up as a change too: add it here with its current value.
resource "aws_backup_region_settings" "this" {
  resource_type_opt_in_preference = {
    "Aurora"                 = true
    "CloudFormation"         = true
    "DSQL"                   = true
    "DocumentDB"             = true
    "DynamoDB"               = true
    "EBS"                    = true
    "EC2"                    = true
    "EFS"                    = true
    "EKS"                    = true
    "FSx"                    = true
    "Neptune"                = true
    "RDS"                    = true
    "Redshift"               = true
    "Redshift Serverless"    = true
    "S3"                     = true
    "SAP HANA on Amazon EC2" = true
    "Storage Gateway"        = true
    "VirtualMachine"         = true
  }
}

resource "aws_backup_vault" "this" {
  name = "v1be-cafe"

  # This is where the recovery points live, so losing it loses the backups.
  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "backup_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

# ADR-0011: a café CI role may pass this exact role to AWS Backup, and no other.
# The v1be-infra- prefix also puts it out of reach of the apply role.
resource "aws_iam_role" "backup" {
  name               = "v1be-infra-backup"
  description        = "Lets AWS Backup snapshot and restore the café DSQL cluster."
  assume_role_policy = data.aws_iam_policy_document.backup_trust.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset(["Backup", "Restores"])

  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyFor${each.key}"
}

resource "aws_backup_plan" "weekly" {
  name = "v1be-cafe-weekly"

  rule {
    rule_name         = "weekly"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 19 ? * SAT *)" # 03:00 on Sunday, UTC+8

    # A DSQL backup can take up to an hour just to start.
    start_window      = 120
    completion_window = 480

    lifecycle {
      delete_after = 14
    }
  }
}

# The café's DSQL cluster must carry this tag, or it isn't backed up. AWS documents
# picking DSQL clusters by tag, and no cluster exists yet to prove a wildcard ARN.
resource "aws_backup_selection" "tagged" {
  name         = "v1be-cafe-tagged"
  plan_id      = aws_backup_plan.weekly.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "backup"
    value = "weekly"
  }

  depends_on = [aws_iam_role_policy_attachment.backup]
}
