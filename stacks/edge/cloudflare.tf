data "cloudflare_zone" "this" {
  for_each = local.zones

  filter = {
    name = each.key
  }
}

resource "cloudflare_zone_setting" "ssl" {
  for_each = local.zones

  zone_id    = data.cloudflare_zone.this[each.key].zone_id
  setting_id = "ssl"
  value      = "strict"
}

# The rules below match every proxied hostname in the zone, so a proxied record
# must only ever point at this series' CloudFront. Any other origin would receive
# the secret.
resource "cloudflare_ruleset" "origin_header" {
  for_each = local.zones

  zone_id = data.cloudflare_zone.this[each.key].zone_id
  name    = "v1be origin header"
  kind    = "zone"
  phase   = "http_request_late_transform"

  rules = [{
    ref         = "add_origin_header"
    description = "Prove to CloudFront that a request came through Cloudflare (ADR-0010)."
    expression  = "true"
    action      = "rewrite"

    action_parameters = {
      headers = {
        (local.origin_header) = {
          operation = "set"
          value     = random_password.origin_secret.result
        }
      }
    }
  }]
}

# CloudFront is the only cache, so a deploy has one cache to clear (ADR-0010).
resource "cloudflare_ruleset" "cache_bypass" {
  for_each = local.zones

  zone_id = data.cloudflare_zone.this[each.key].zone_id
  name    = "v1be cache bypass"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [{
    ref         = "bypass_cache"
    description = "Leave all caching to CloudFront (ADR-0010)."
    expression  = "true"
    action      = "set_cache_settings"

    action_parameters = {
      cache = false
    }
  }]
}

# The free plan's one rate-limit rule, shared by every episode: a coarse flood
# guard, with each episode's real limits in the app. The free plan only allows a
# 10-second period and timeout, and no regex.
resource "cloudflare_ruleset" "rate_limit" {
  for_each = local.zones

  zone_id = data.cloudflare_zone.this[each.key].zone_id
  name    = "v1be rate limit"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [{
    ref         = "limit_api"
    description = "Block one IP flooding any episode's API (ADR-0010)."
    expression  = "http.request.uri.path wildcard \"/api/*\""
    action      = "block"

    ratelimit = {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = 10
      requests_per_period = 50
      mitigation_timeout  = 10
    }
  }]
}
