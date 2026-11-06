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
}

resource "github_organization_settings" "this" {
  billing_email = var.root_email
  name          = "V1be Coding"
  description   = "A build series: each app goes from spec to deployed in one agent run."

  # v1be-bot gets write access repo by repo, and only owners create repos.
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
  for_each = local.repositories

  name        = each.key
  description = each.value.description
  visibility  = "public"
  is_template = each.value.is_template

  # Branch rules need a main branch to exist.
  auto_init = true

  # Runs land through auto-merge, so only the required check decides (ADR-0013).
  allow_auto_merge = each.key == "episode-template"

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

resource "github_repository_collaborator" "bot" {
  for_each = local.repositories

  repository = github_repository.this[each.key].name
  username   = "v1be-bot"
  permission = "push"
}

locals {
  # The only person who can push or merge to main in v1be-infra (ADR-0012).
  repo_owner = "emilianocasijr"

  # GitHub's own app ID for GitHub Actions, so only Actions can report the check.
  github_actions_app_id = 15368
}

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

# The template's rules. Episode repos will get the same ones (ADR-0013).
resource "github_branch_protection_v3" "template_main" {
  repository     = github_repository.this["episode-template"].name
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

# PR branches reach these, so they have no branch policy.
resource "github_repository_environment" "template" {
  for_each = toset(["checklist", "cost"])

  repository          = github_repository.this["episode-template"].name
  environment         = each.key
  can_admins_bypass   = false
  prevent_self_review = false

  reviewers {
    users = [data.github_user.repo_owner.id]
  }
}

resource "github_issue_label" "failed_attempt" {
  repository  = github_repository.this["episode-template"].name
  name        = "failed-attempt"
  color       = "b60205"
  description = "An attempt that failed and went back to the spec."
}

# Episode CI builds role ARNs from these, so IDs stay masked in public logs.
resource "github_actions_organization_secret" "account_id" {
  for_each = local.member_accounts

  secret_name     = "${upper(each.key)}_ACCOUNT_ID"
  visibility      = "all"
  plaintext_value = aws_organizations_account.member[each.key].id
}

# How the template knows which episode it's deploying. Phase F's repos get the same.
resource "github_actions_variable" "template" {
  for_each = {
    EPISODE = "smoke-test"
    ACCOUNT = "portfolio"
  }

  repository    = github_repository.this["episode-template"].name
  variable_name = each.key
  value         = each.value
}
