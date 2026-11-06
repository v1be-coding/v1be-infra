terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.69.1"
    }
  }
}

# State stays in the management account, so the backend signs in with AWS_PROFILE.
# Everything else happens in the member account, through this profile (ADR-0012).
provider "aws" {
  region              = "ap-southeast-1"
  profile             = var.aws_profile
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      project    = "v1be"
      stack      = "accounts"
      managed_by = "terraform"
    }
  }
}
