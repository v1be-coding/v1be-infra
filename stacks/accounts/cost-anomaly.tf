# ADR-0007: the "Notice" guard. It's free, and each account can have one monitor
# of this type. The wizard imports the one AWS may have made by default.
resource "aws_ce_anomaly_monitor" "services" {
  name              = "v1be-${var.account}-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

# Daily, to keep the inbox quiet. Instant alerts would go through the topic in
# alerts.tf.
resource "aws_ce_anomaly_subscription" "email" {
  name             = "v1be-${var.account}-daily"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.services.arn]

  subscriber {
    type    = "EMAIL"
    address = var.root_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["1"]
    }
  }
}
