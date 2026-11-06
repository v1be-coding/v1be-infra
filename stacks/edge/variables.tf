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
  description = "The series' episodes, from stacks/episodes.tfvars. This stack only reads each one's zone."
  type = map(object({
    account   = string
    subdomain = string
    anthropic = optional(bool, false)
    zone      = optional(string)
  }))
  default = {}
}
