terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.69.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.28.1"
    }
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
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

# CloudFront only reads certificates from us-east-1.
provider "aws" {
  alias               = "portfolio_us_east_1"
  region              = "us-east-1"
  profile             = "portfolio"
  allowed_account_ids = [var.portfolio_account_id]

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias               = "cafe_us_east_1"
  region              = "us-east-1"
  profile             = "cafe"
  allowed_account_ids = [var.cafe_account_id]

  default_tags {
    tags = local.tags
  }
}

# Reads CLOUDFLARE_API_TOKEN, so the token stays out of code and state.
provider "cloudflare" {}

# No token: this only reads public repo IDs, so CI holds no GitHub login (ADR-0012).
provider "github" {
  owner = "v1be-coding"
}
