# Production's edge. It's here, not in the template, so a run can't remove the
# header check and read the origin secret (ADR-0010). A run deploys into the
# bucket and the API, and can't change the distribution.

# Closes the API's raw execute-api address (Q55). CloudFront sends this on every
# API request, and the Lambda refuses any request without it, so a caller can't
# skip CloudFront or forge CF-Connecting-IP. It guards against outsiders only:
# anything that can read the distribution can read it. The template reads it
# from SSM, so it stays marked sensitive and out of the public logs.
resource "random_password" "api_origin" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "api_origin" {
  name  = "/${var.name}/internal/api-origin"
  type  = "SecureString"
  value = random_password.api_origin.result
}

data "aws_cloudfront_function" "origin_check" {
  name  = "v1be-origin-check"
  stage = "LIVE"
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "api" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_s3_bucket" "site" {
  bucket        = local.site_bucket
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "site" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site.json
}

# Only the shell. The template adds its routes and stage. The tag is what lets
# this episode's CI role touch it.
resource "aws_apigatewayv2_api" "api" {
  name          = local.api_name
  protocol_type = "HTTP"

  tags = {
    episode = var.name
  }
}

resource "aws_acm_certificate" "site" {
  provider = aws.us_east_1

  domain_name       = var.hostname
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Not proxied: ACM must read the record itself.
resource "cloudflare_dns_record" "validation" {
  zone_id = var.zone_id
  name    = trimsuffix(tolist(aws_acm_certificate.site.domain_validation_options)[0].resource_record_name, ".")
  type    = tolist(aws_acm_certificate.site.domain_validation_options)[0].resource_record_type
  content = trimsuffix(tolist(aws_acm_certificate.site.domain_validation_options)[0].resource_record_value, ".")
  ttl     = 60
  proxied = false
}

resource "aws_acm_certificate_validation" "site" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [tolist(aws_acm_certificate.site.domain_validation_options)[0].resource_record_name]
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "${var.name}, ${var.account}"
  aliases             = [var.hostname]
  default_root_object = "index.html"
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_200"

  origin {
    origin_id                = "site"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = var.origin_access_control_id
  }

  origin {
    origin_id   = "api"
    domain_name = replace(aws_apigatewayv2_api.api.api_endpoint, "https://", "")

    # CloudFront replaces any value a caller sends with this one.
    custom_header {
      name  = "x-v1be-api-origin"
      value = random_password.api_origin.result
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimized.id
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = data.aws_cloudfront_function.origin_check.arn
    }
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.api.id
    compress                 = true

    function_association {
      event_type   = "viewer-request"
      function_arn = data.aws_cloudfront_function.origin_check.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Proxied records receive the origin secret, so this must only ever point at a
# distribution this stack made (edge stack, cloudflare.tf).
resource "cloudflare_dns_record" "site" {
  zone_id = var.zone_id
  name    = var.hostname
  type    = "CNAME"
  content = aws_cloudfront_distribution.site.domain_name
  ttl     = 1
  proxied = true
}
