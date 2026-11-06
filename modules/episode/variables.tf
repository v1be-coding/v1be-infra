variable "name" {
  description = "The episode's name, as in stacks/episodes.tfvars."
  type        = string
}

variable "account" {
  description = "The account this role lives in: portfolio or cafe."
  type        = string
}

variable "account_id" {
  description = "That account's ID, so policies name exact resources."
  type        = string
}

variable "repo_sub" {
  description = "The repo part of GitHub's token subject, with numeric IDs."
  type        = string
}

variable "oidc_provider_arn" {
  description = "GitHub's OIDC login in this account, from the accounts stack."
  type        = string
}
