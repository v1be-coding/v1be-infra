variable "portfolio_account_id" {
  description = "Portfolio's account ID. Terraform refuses to run against any other, and it stays out of this public repo."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.portfolio_account_id))
    error_message = "Use the 12-digit account ID."
  }
}

variable "cafe_account_id" {
  description = "The café's account ID. Terraform refuses to run against any other, and it stays out of this public repo."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.cafe_account_id))
    error_message = "Use the 12-digit account ID."
  }
}

variable "episodes" {
  description = "The series' episodes, from stacks/episodes.tfvars. `repo` defaults to the episode's name, and `repo_id` is its repo's numeric ID."
  type = map(object({
    account   = string
    subdomain = string
    anthropic = optional(bool, false)
    pages     = optional(bool, false)
    zone      = optional(string)
    repo      = optional(string)
    repo_id   = optional(number)
  }))
  default = {}

  # The CI role trusts the repo by name and numeric ID. The ID exists only once
  # org has made the repo, so an episode's first plan stops here until a PR adds it
  # (docs/adding-an-episode.md, step 3c).
  validation {
    condition     = alltrue([for episode in var.episodes : episode.repo_id != null])
    error_message = "Each episode needs repo_id, its repo's numeric ID: gh api repos/v1be-coding/<repo> --jq .id, once org has made the repo."
  }

  validation {
    condition     = alltrue([for episode in var.episodes : contains(["portfolio", "cafe"], episode.account)])
    error_message = "Each episode's account must be portfolio or cafe."
  }

  # An empty subdomain is the zone's apex. A café episode can't take it, as its
  # demo needs a -demo address beside production's.
  validation {
    condition     = alltrue([for episode in var.episodes : episode.subdomain != "" || episode.account == "portfolio"])
    error_message = "Only a portfolio episode can take the zone's apex (an empty subdomain)."
  }
}
