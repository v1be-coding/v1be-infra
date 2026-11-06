locals {
  main_zone = "emilianocasijr.com"
  zones     = toset(concat([local.main_zone], compact([for episode in var.episodes : episode.zone])))

  origin_header = "x-origin-verify"

  tags = {
    project    = "v1be"
    stack      = "edge"
    managed_by = "terraform"
  }
}

# Neither provider marks these fields as sensitive, so the mark from this resource
# is all that keeps the value out of the public logs. Only pass it straight through,
# because a function like nonsensitive() or a plain output would print it.
resource "random_password" "origin_secret" {
  length  = 64
  special = false
}

# A KeyValueStore only works with a function in its own account, so each member
# account gets its own set.
module "portfolio" {
  source = "../../modules/edge-account"

  providers = {
    aws = aws.portfolio
  }

  origin_header = local.origin_header
  origin_secret = random_password.origin_secret.result
}

module "cafe" {
  source = "../../modules/edge-account"

  providers = {
    aws = aws.cafe
  }

  origin_header = local.origin_header
  origin_secret = random_password.origin_secret.result
}
