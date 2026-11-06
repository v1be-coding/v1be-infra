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

variable "hostname" {
  description = "The public address of this target, such as ulam.example.com."
  type        = string
}

variable "zone_id" {
  description = "The Cloudflare zone that holds the hostname."
  type        = string
}

variable "origin_access_control_id" {
  description = "The edge stack's origin access control in this account."
  type        = string
}
