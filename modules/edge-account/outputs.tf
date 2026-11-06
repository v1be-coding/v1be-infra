output "origin_access_control_id" {
  description = "ID of the origin access control for private S3 sites."
  value       = aws_cloudfront_origin_access_control.s3.id
}

output "origin_check_function_name" {
  description = "Name of the header-check function."
  value       = aws_cloudfront_function.origin_check.name
}
