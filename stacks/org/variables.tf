variable "root_email" {
  description = "Mailbox for root emails and alerts, with no plus tag. Each use adds its own, so the address stays out of this public repo."
  type        = string

  validation {
    condition     = can(regex("^[^@+]+@[^@]+$", var.root_email))
    error_message = "Use a plain address with no plus tag, such as name@example.com."
  }
}

# No default, so a plan run without stacks/episodes.tfvars fails rather than
# removing every episode repo.
variable "episodes" {
  description = "The series' episodes, from stacks/episodes.tfvars. `org` makes each episode's repo from the template."
  type = map(object({
    account   = string
    subdomain = string
    anthropic = optional(bool, false)
    zone      = optional(string)
    repo      = optional(string)
  }))

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
