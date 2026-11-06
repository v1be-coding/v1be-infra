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
