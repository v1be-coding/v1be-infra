# The first run leaves this file out and starts on local state, because the
# bucket doesn't exist yet. See sandbox/wizards/org-bootstrap.sh.
terraform {
  backend "s3" {
    bucket       = "v1be-org-state"
    key          = "org/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
