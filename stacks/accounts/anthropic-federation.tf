# Lets an episode's Lambda prove its role to Anthropic with a short-lived AWS
# token, so no Anthropic key is stored anywhere (workload identity federation).
# It's one switch for the whole account, so it lives here and not in an episode.
# Each episode's boundary still decides which roles may ask for a token.
resource "aws_iam_outbound_web_identity_federation" "anthropic" {
  count = local.is_portfolio ? 1 : 0
}
