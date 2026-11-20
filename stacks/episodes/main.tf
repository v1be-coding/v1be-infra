locals {
  github_owner_id = 352848052
  main_zone       = "emilianocasijr.com"

  tags = {
    project    = "v1be"
    stack      = "episodes"
    managed_by = "terraform"
  }

  repos = { for name, episode in var.episodes : name => coalesce(episode.repo, name) }
  zones = { for name, episode in var.episodes : name => coalesce(episode.zone, local.main_zone) }

  # Each episode's address in portfolio. An empty subdomain is the zone's apex, and
  # a café episode's demo takes a -demo address, as production has the plain one.
  portfolio_hostnames = {
    for name, episode in var.episodes : name => (
      episode.subdomain == "" ? local.zones[name] : "${episode.subdomain}${episode.account == "cafe" ? "-demo" : ""}.${local.zones[name]}"
    )
  }

  # Numeric IDs survive a rename, so a new repo can't take over this trust. They
  # come from tfvars, not a lookup: an unauthenticated GitHub call hung two applies
  # until they timed out, and a lookup would trust a recreated repo silently.
  repo_subs = {
    for name, repo in local.repos :
    name => "repo:v1be-coding@${local.github_owner_id}/${repo}@${var.episodes[name].repo_id}"
  }
}

data "cloudflare_zone" "episode" {
  for_each = toset(values(local.zones))

  filter = {
    name = each.key
  }
}

# The edge stack's outputs aren't secret, and this reads only those.
data "terraform_remote_state" "edge" {
  backend = "s3"

  config = {
    bucket = "v1be-infra-state"
    key    = "edge/terraform.tfstate"
    region = "ap-southeast-1"
  }
}

data "aws_iam_openid_connect_provider" "portfolio" {
  provider = aws.portfolio

  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_openid_connect_provider" "cafe" {
  provider = aws.cafe

  url = "https://token.actions.githubusercontent.com"
}

# A café episode's demo lives in portfolio too (ADR-0005), so every episode gets
# a target here. The demo takes a -demo address, as production has the plain one.
module "portfolio" {
  source   = "../../modules/episode"
  for_each = var.episodes

  providers = {
    aws           = aws.portfolio
    aws.us_east_1 = aws.portfolio_us_east_1
  }

  name                     = each.key
  account                  = "portfolio"
  account_id               = var.portfolio_account_id
  repo_sub                 = local.repo_subs[each.key]
  anthropic                = each.value.anthropic
  pages                    = each.value.pages
  oidc_provider_arn        = data.aws_iam_openid_connect_provider.portfolio.arn
  hostname                 = local.portfolio_hostnames[each.key]
  zone_id                  = data.cloudflare_zone.episode[local.zones[each.key]].zone_id
  origin_access_control_id = data.terraform_remote_state.edge.outputs.origin_access_control_ids.portfolio
}

module "cafe" {
  source   = "../../modules/episode"
  for_each = { for name, episode in var.episodes : name => episode if episode.account == "cafe" }

  providers = {
    aws           = aws.cafe
    aws.us_east_1 = aws.cafe_us_east_1
  }

  name                     = each.key
  account                  = "cafe"
  account_id               = var.cafe_account_id
  repo_sub                 = local.repo_subs[each.key]
  anthropic                = each.value.anthropic
  pages                    = each.value.pages
  oidc_provider_arn        = data.aws_iam_openid_connect_provider.cafe.arn
  hostname                 = "${each.value.subdomain}.${local.zones[each.key]}"
  zone_id                  = data.cloudflare_zone.episode[local.zones[each.key]].zone_id
  origin_access_control_id = data.terraform_remote_state.edge.outputs.origin_access_control_ids.cafe
}

# Throwaway: a change, so deploy-episodes runs an apply (it skips one when the
# plan has no changes), and the apply writes state without #62's removed
# github_repository data. The next PR removes this and the github provider.
resource "terraform_data" "state_cleanup" {}
