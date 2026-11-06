variable "account" {
  description = "Which member account this run is for."
  type        = string

  validation {
    condition     = contains(["portfolio", "cafe"], var.account)
    error_message = "Use portfolio or cafe."
  }
}

variable "account_id" {
  description = "That account's ID. Terraform refuses to run against any other, and it stays out of this public repo."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Use the 12-digit account ID."
  }
}

variable "aws_profile" {
  description = "AWS CLI profile that signs in to the member account."
  type        = string
}

variable "root_email" {
  description = "Mailbox for cost alerts, with no plus tag, so the address stays out of this public repo."
  type        = string

  validation {
    condition     = can(regex("^[^@+]+@[^@]+$", var.root_email))
    error_message = "Use a plain address with no plus tag, such as name@example.com."
  }
}
