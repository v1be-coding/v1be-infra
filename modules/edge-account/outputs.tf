output "origin_access_control_id" {
  description = "ID of the origin access control for private S3 sites."
  value       = aws_cloudfront_origin_access_control.s3.id
}

output "origin_check_function_name" {
  description = "Name of the header-check function."
  value       = aws_cloudfront_function.origin_check.name
}

output "origin_check_pages_function_name" {
  description = "Name of the header-check function with clean URLs for prerendered pages."
  value       = aws_cloudfront_function.origin_check_pages.name
}

output "pages_function_name" {
  description = "Name of the clean-URL function for branch environments, with no origin check."
  value       = aws_cloudfront_function.pages.name
}
