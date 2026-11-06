terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.69.1"
    }
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
  }
}

# CI writes these profiles, one per member account, for the current environment.
provider "aws" {
  alias               = "portfolio"
  region              = "ap-southeast-1"
  profile             = "portfolio"
  allowed_account_ids = [var.portfolio_account_id]

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias               = "cafe"
  region              = "ap-southeast-1"
  profile             = "cafe"
  allowed_account_ids = [var.cafe_account_id]

  default_tags {
    tags = local.tags
  }
}

# No token: this only reads public repo IDs, so CI holds no GitHub login (ADR-0012).
provider "github" {
  owner = "v1be-coding"
}
