# Episode alarms email through this topic (Q61). Episodes build its ARN from the
# name, so their CI needs no SNS rights. This stack runs only in the Sandbox, so
# the address stays out of the public CI logs.
resource "aws_sns_topic" "alerts" {
  name = "v1be-alerts"
}

# Only this account's v1be-* alarms can publish here.
data "aws_iam_policy_document" "alerts" {
  statement {
    sid       = "EpisodeAlarms"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudwatch:ap-southeast-1:${var.account_id}:alarm:v1be-*"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

# Stays pending until the wizard confirms it with --authenticate-on-unsubscribe,
# so someone sent a forwarded alert can't unsubscribe you.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.root_email
}
