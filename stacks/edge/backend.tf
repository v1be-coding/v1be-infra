# One state, because every zone and account shares one origin secret (ADR-0009).
# CI's AWS_PROFILE picks the portfolio role, as the café's roles can't reach this
# bucket.
terraform {
  backend "s3" {
    bucket       = "v1be-infra-state"
    key          = "edge/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
