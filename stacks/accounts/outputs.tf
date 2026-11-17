output "ci_role_names" {
  description = "Roles v1be-infra CI signs in to."
  value       = sort([for role in aws_iam_role.ci : role.name])
}

output "token_issuer" {
  description = "This account's token issuer URL, for Anthropic's Connect workload wizard. Empty in the café."
  value       = one(aws_iam_outbound_web_identity_federation.anthropic[*].issuer_identifier)
}

output "state_buckets" {
  description = "State buckets in this account."
  value = compact([
    "v1be-${var.account}-state",
    local.is_portfolio ? "v1be-infra-state" : "",
  ])
}
