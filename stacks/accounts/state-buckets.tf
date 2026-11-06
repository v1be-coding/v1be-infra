# Every account gets a bucket for episode app state. portfolio also holds
# v1be-infra-state, for edge and episodes, so CI never reaches the management
# account (ADR-0012). claude-readonly is denied every v1be-*state* bucket.
module "state_bucket" {
  source = "../../modules/state-bucket"

  name = "v1be-${var.account}-state"
}

module "infra_state_bucket" {
  count  = local.is_portfolio ? 1 : 0
  source = "../../modules/state-bucket"

  name = "v1be-infra-state"
}
