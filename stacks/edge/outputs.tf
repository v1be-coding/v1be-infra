# Not secret. The episodes stack and the template's CloudFront module use these.
output "origin_access_control_ids" {
  description = "The origin access control for private S3 sites, by account."
  value = {
    portfolio = module.portfolio.origin_access_control_id
    cafe      = module.cafe.origin_access_control_id
  }
}

output "origin_check_function_name" {
  description = "The header-check function, with this name in both accounts."
  value       = module.portfolio.origin_check_function_name
}
