locals {
  repositories = {
    ".github" = {
      description = "The v1be-coding org profile."
      is_template = false
    }
    "episode-template" = {
      description = "Where every V1be Coding episode starts."
      is_template = true
    }
    "series" = {
      description = "The rules, glossary and decisions behind V1be Coding."
      is_template = false
    }
    "v1be-infra" = {
      description = "The Foundation: AWS accounts, guardrails and shared infrastructure."
      is_template = false
    }
  }

  main_zone = "emilianocasijr.com"

  # Each episode's repo, and what its CI is told. An episode whose repo is the
  # template, as smoke-test was until phase F, puts the template in here too.
  episode_repos = {
    for name, episode in var.episodes : coalesce(episode.repo, name) => {
      EPISODE  = name
      ACCOUNT  = episode.account
      SITE_URL = "https://${episode.subdomain == "" ? "" : "${episode.subdomain}."}${coalesce(episode.zone, local.main_zone)}"
    }
  }

  # Repos made from the template, one for each episode with its own repo.
  generated_repos = {
    for repo, vars in local.episode_repos : repo => {
      description = "The ${vars.EPISODE} episode of V1be Coding."
      is_template = false
    } if repo != "episode-template"
  }

  # The template and every repo made from it get the same rules (ADR-0013).
  ruled_repos = setunion(["episode-template"], keys(local.generated_repos))
}

resource "github_organization_settings" "this" {
  billing_email = var.root_email
  name          = "V1be Coding"
  description   = "A build series: each app goes from spec to deployed in one agent run."

  # The agent reaches repos through its App, and only owners create repos.
  default_repository_permission           = "read"
  members_can_create_repositories         = false
  members_can_create_public_repositories  = false
  members_can_create_private_repositories = false
  members_can_create_pages                = false
  members_can_create_public_pages         = false
  members_can_create_private_pages        = false
  members_can_fork_private_repositories   = false
}

resource "github_repository" "this" {
  for_each = merge(local.repositories, local.generated_repos)

  name        = each.key
  description = each.value.description
  visibility  = "public"
  is_template = each.value.is_template

  # Branch rules need a main branch. An episode repo gets one from the template.
  auto_init = !contains(keys(local.generated_repos), each.key)

  dynamic "template" {
    for_each = contains(keys(local.generated_repos), each.key) ? [1] : []

    content {
      owner      = "v1be-coding"
      repository = "episode-template"
    }
  }

  # Runs land through auto-merge, so only the required check decides (ADR-0013).
  allow_auto_merge = contains(local.ruled_repos, each.key)

  has_issues   = true
  has_wiki     = false
  has_projects = false

  allow_merge_commit     = false
  allow_rebase_merge     = false
  allow_squash_merge     = true
  delete_branch_on_merge = true

  # Destroying this resource archives the repo and keeps its history.
  archive_on_destroy = true

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }
}

locals {
  # The only person who can push or merge to main in v1be-infra (ADR-0012).
  repo_owner = "emilianocasijr"

  # GitHub's own app ID for GitHub Actions, so only Actions can report the check.
  github_actions_app_id = 15368
}

# The v1be-agent App is installed on selected repos only, and this stack doesn't
# add a new repo to it: GitHub refused the wizard's `gh` login token for that
# ("You do not have permission to modify this app", #49's apply, 2026-11-19).
# The user adds each new episode repo by hand in Setup (adding-an-episode.md).

data "github_user" "repo_owner" {
  username = local.repo_owner
}

resource "github_branch_protection_v3" "infra_main" {
  repository     = github_repository.this["v1be-infra"].name
  branch         = "main"
  enforce_admins = true

  required_status_checks {
    strict = false
    checks = ["risky-text:${local.github_actions_app_id}"]
  }

  # A PR is required, with no approvals, because the user can't approve their own.
  required_pull_request_reviews {
    required_approving_review_count = 0
  }

  restrictions {
    users = [local.repo_owner]
  }
}

resource "github_repository_environment" "infra" {
  for_each = toset(["plan", "apply"])

  repository          = github_repository.this["v1be-infra"].name
  environment         = each.key
  can_admins_bypass   = false
  prevent_self_review = false

  # apply waits for the user's approval, and plan runs without waiting.
  dynamic "reviewers" {
    for_each = each.key == "apply" ? [1] : []

    content {
      users = [data.github_user.repo_owner.id]
    }
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "infra_main" {
  for_each = toset(["plan", "apply"])

  repository     = github_repository.this["v1be-infra"].name
  environment    = github_repository_environment.infra[each.key].environment
  branch_pattern = "main"
}

# The template's rules, which every episode repo also gets (ADR-0013).
resource "github_branch_protection_v3" "episode_main" {
  for_each = local.ruled_repos

  repository     = github_repository.this[each.key].name
  branch         = "main"
  enforce_admins = true

  required_status_checks {
    strict = false
    checks = ["green:${local.github_actions_app_id}"]
  }

  # No approvals in general. Code owner review guards the frozen tests.
  required_pull_request_reviews {
    required_approving_review_count = 0
    require_code_owner_reviews      = true
  }
}

moved {
  from = github_branch_protection_v3.template_main
  to   = github_branch_protection_v3.episode_main["episode-template"]
}

# PR branches reach these, so they have no branch policy.
resource "github_repository_environment" "episode" {
  for_each = toset([
    for pair in setproduct(local.ruled_repos, ["checklist", "cost"]) : join("/", pair)
  ])

  repository          = github_repository.this[split("/", each.key)[0]].name
  environment         = split("/", each.key)[1]
  can_admins_bypass   = false
  prevent_self_review = false

  reviewers {
    users = [data.github_user.repo_owner.id]
  }
}

moved {
  from = github_repository_environment.template["checklist"]
  to   = github_repository_environment.episode["episode-template/checklist"]
}

moved {
  from = github_repository_environment.template["cost"]
  to   = github_repository_environment.episode["episode-template/cost"]
}

resource "github_issue_label" "failed_attempt" {
  for_each = local.ruled_repos

  repository  = github_repository.this[each.key].name
  name        = "failed-attempt"
  color       = "b60205"
  description = "An attempt that failed and went back to the spec."
}

moved {
  from = github_issue_label.failed_attempt
  to   = github_issue_label.failed_attempt["episode-template"]
}

# Episode CI builds role ARNs from these, so IDs stay masked in public logs.
resource "github_actions_organization_secret" "account_id" {
  for_each = local.member_accounts

  secret_name     = "${upper(each.key)}_ACCOUNT_ID"
  visibility      = "all"
  plaintext_value = aws_organizations_account.member[each.key].id
}

# How each repo knows which episode it's deploying.
resource "github_actions_variable" "episode" {
  for_each = merge([
    for repo, vars in local.episode_repos : {
      for name, value in vars : "${repo}/${name}" => { repo = repo, name = name, value = value }
    }
  ]...)

  repository    = github_repository.this[each.value.repo].name
  variable_name = each.value.name
  value         = each.value.value
}

moved {
  from = github_actions_variable.template["EPISODE"]
  to   = github_actions_variable.episode["episode-template/EPISODE"]
}

moved {
  from = github_actions_variable.template["ACCOUNT"]
  to   = github_actions_variable.episode["episode-template/ACCOUNT"]
}

moved {
  from = github_actions_variable.template["SITE_URL"]
  to   = github_actions_variable.episode["episode-template/SITE_URL"]
}
