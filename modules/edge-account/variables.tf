variable "origin_header" {
  description = "Name of the header Cloudflare adds."
  type        = string
}

variable "origin_secret" {
  description = "The value Cloudflare sends in that header."
  type        = string
  sensitive   = true
}
