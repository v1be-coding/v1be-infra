locals {
  github_owner_id = 352848052

  tags = {
    project    = "v1be"
    stack      = "episodes"
    managed_by = "terraform"
  }

  repos = { for name, episode in var.episodes : name => coalesce(episode.repo, name) }

  # Numeric IDs survive a rename, so a new repo can't take over this trust.
  repo_subs = {
    for name, repo in local.repos :
    name => "repo:v1be-coding@${local.github_owner_id}/${repo}@${data.github_repository.episode[name].repo_id}"
  }
}

data "github_repository" "episode" {
  for_each = local.repos

  full_name = "v1be-coding/${each.value}"
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
# a role here.
module "portfolio" {
  source   = "../../modules/episode"
  for_each = var.episodes

  providers = {
    aws = aws.portfolio
  }

  name              = each.key
  account           = "portfolio"
  account_id        = var.portfolio_account_id
  repo_sub          = local.repo_subs[each.key]
  oidc_provider_arn = data.aws_iam_openid_connect_provider.portfolio.arn
}

module "cafe" {
  source   = "../../modules/episode"
  for_each = { for name, episode in var.episodes : name => episode if episode.account == "cafe" }

  providers = {
    aws = aws.cafe
  }

  name              = each.key
  account           = "cafe"
  account_id        = var.cafe_account_id
  repo_sub          = local.repo_subs[each.key]
  oidc_provider_arn = data.aws_iam_openid_connect_provider.cafe.arn
}
