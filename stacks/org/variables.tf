variable "root_email" {
  description = "Mailbox for root emails and alerts, with no plus tag. Each use adds its own, so the address stays out of this public repo."
  type        = string

  validation {
    condition     = can(regex("^[^@+]+@[^@]+$", var.root_email))
    error_message = "Use a plain address with no plus tag, such as name@example.com."
  }
}
