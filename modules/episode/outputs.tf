output "ci_role_name" {
  description = "The role this episode's CI signs in to."
  value       = aws_iam_role.ci.name
}

output "boundary_name" {
  description = "The boundary every role made by CI must carry."
  value       = aws_iam_policy.boundary.name
}
