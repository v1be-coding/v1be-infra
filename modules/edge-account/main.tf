locals {
  store_key = "origin-secret"
}

# The value lives here because a CloudFront Function can't call SSM (ADR-0009).
resource "aws_cloudfront_key_value_store" "origin" {
  name    = "v1be-origin"
  comment = "The origin header value that proves a request came through Cloudflare."
}

resource "aws_cloudfrontkeyvaluestore_key" "origin_secret" {
  key_value_store_arn = aws_cloudfront_key_value_store.origin.arn
  key                 = local.store_key
  value               = var.origin_secret
}

# Episodes attach this to production distributions, and CI can't edit it (ADR-0010).
# It fails closed, so an unreadable store refuses traffic. It removes the header
# after checking, so the secret never reaches an app or its logs.
resource "aws_cloudfront_function" "origin_check" {
  name    = "v1be-origin-check"
  runtime = "cloudfront-js-2.0"
  comment = "Rejects requests that didn't come through Cloudflare."
  publish = true

  key_value_store_associations = [aws_cloudfront_key_value_store.origin.arn]

  code = <<-JS
    import cf from 'cloudfront';

    const store = cf.kvs();

    async function handler(event) {
      const request = event.request;
      const sent = request.headers['${var.origin_header}'];
      let expected;
      try {
        expected = await store.get('${local.store_key}');
      } catch (err) {
        expected = undefined;
      }
      if (!sent || !expected || sent.value !== expected) {
        return { statusCode: 403, statusDescription: 'Forbidden' };
      }
      delete request.headers['${var.origin_header}'];
      return request;
    }
  JS
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "v1be-s3"
  description                       = "Lets CloudFront read private S3 sites."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
