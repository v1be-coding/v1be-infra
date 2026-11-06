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

# Sign-in comes from AWS_PROFILE in the Sandbox, never from this repo (ADR-0012).
provider "aws" {
  region = "ap-southeast-1"

  default_tags {
    tags = {
      project    = "v1be"
      stack      = "org"
      managed_by = "terraform"
    }
  }
}

# The token comes from GITHUB_TOKEN in the Sandbox, set by the wizard for one run.
provider "github" {
  owner = "v1be-coding"
}
