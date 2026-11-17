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

# The same check, for a site of prerendered pages, where each page is a folder's
# index.html. An episode opts in with `pages = true`. A behaviour can have only
# one viewer-request function, so this can't be a second function after the
# check. Keep the check identical to origin_check's above.
#   /about/   -> 301 to /about, with the query string kept
#   /about    -> /about/index.html, read from the bucket
#   /app.js   -> unchanged, because the last segment has a dot
resource "aws_cloudfront_function" "origin_check_pages" {
  name    = "v1be-origin-check-pages"
  runtime = "cloudfront-js-2.0"
  comment = "The origin check, plus clean URLs for prerendered pages."
  publish = true

  key_value_store_associations = [aws_cloudfront_key_value_store.origin.arn]

  code = <<-JS
    import cf from 'cloudfront';

    const store = cf.kvs();

    function queryString(qs) {
      const parts = [];
      // Runtime 2.0 has for and for-in, but not for-of.
      for (var name in qs) {
        var item = qs[name];
        var values = item.multiValue ? item.multiValue : [item];
        for (var i = 0; i < values.length; i++) {
          parts.push(values[i].value === '' ? name : name + '=' + values[i].value);
        }
      }
      return parts.length ? '?' + parts.join('&') : '';
    }

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

      const uri = request.uri;
      if (uri.length > 1 && uri.endsWith('/')) {
        const path = uri.replace(/\/+$/, '') || '/';
        return {
          statusCode: 301,
          statusDescription: 'Moved Permanently',
          headers: { location: { value: path + queryString(request.querystring) } },
        };
      }
      const last = uri.substring(uri.lastIndexOf('/') + 1);
      if (uri !== '/' && last.indexOf('.') === -1) {
        request.uri = uri + '/index.html';
      }
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
