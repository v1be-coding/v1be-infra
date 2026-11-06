# The stack runs once per member account, and each run has its own state. The
# wizard adds the key, as accounts/<account>/terraform.tfstate.
terraform {
  backend "s3" {
    bucket       = "v1be-org-state"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
