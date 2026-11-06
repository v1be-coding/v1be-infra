output "member_account_names" {
  description = "Names of the accounts this stack created."
  value       = sort([for account in aws_organizations_account.member : account.name])
}

output "state_bucket" {
  description = "Bucket that holds org and accounts state."
  value       = aws_s3_bucket.state.bucket
}
