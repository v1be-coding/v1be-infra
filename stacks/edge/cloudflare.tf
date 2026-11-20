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

# Off so Cloudflare doesn't rewrite email addresses in an episode's prerendered
# HTML or inject its decode script, which breaks hydration and exact-text specs.
resource "cloudflare_zone_setting" "email_obfuscation" {
  for_each = local.zones

  zone_id    = data.cloudflare_zone.this[each.key].zone_id
  setting_id = "email_obfuscation"
  value      = "off"
}

# The other settings that rewrite an episode's HTML, pinned off so a dashboard
# default can't change what production serves. Branch environments skip
# Cloudflare, so only production's smoke run would catch them. Rocket Loader
# rewrites script tags and injects its own loader, which a strict CSP blocks.
# Automatic HTTPS Rewrites edits links in the HTML that React hydrates.
resource "cloudflare_zone_setting" "rocket_loader" {
  for_each = local.zones

  zone_id    = data.cloudflare_zone.this[each.key].zone_id
  setting_id = "rocket_loader"
  value      = "off"
}

resource "cloudflare_zone_setting" "automatic_https_rewrites" {
  for_each = local.zones

  zone_id    = data.cloudflare_zone.this[each.key].zone_id
  setting_id = "automatic_https_rewrites"
  value      = "off"
}

# Two features that would change what production serves stay dashboard settings,
# so the token needs no extra permission. Check both on every zone (the steps are
# in docs/adding-an-episode.md under "A new zone"):
# - Bot Fight Mode: off. While it's on, the free plan can't turn off its JS
#   detections, which inject a /cdn-cgi/ script that the CSP blocks and the
#   served-HTML smoke test fails on. It can also challenge /api/* and the frozen
#   tests' runners, with no rule to exempt them. Pinning it here would need the
#   token's Bot Management Edit.
# - Web Analytics (RUM) automatic setup: disabled, not deleted. Its beacon broke
#   episode 0's CSP. Pinning it would need Account Settings Write, an account-wide
#   permission, and the provider doesn't read `enabled` back anyway.

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
#
# Its blocks never reach AWS, so each episode's rate-limit alarm doesn't count
# them, and the free plan has no alert for them. That split is on purpose
# (2026-11-18): a blocked request costs nothing, and a steady flood still leaks
# about 50 requests per 10 s to the app once each block ends, so the app's limit
# and alarm still see it. The blocks show in the zone's Security Events. The only
# Cloudflare alert is the free HTTP DDoS Attack Alert, by email, set in the
# dashboard (Notifications), as Terraform would need an account-level token and
# the address as a secret.
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
