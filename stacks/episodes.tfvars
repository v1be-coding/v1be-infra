# Every episode in the series. `org` makes each one's repo from the template,
# and `episodes` builds its AWS side. `zone` is optional and defaults to the main zone.
# `repo` is optional and defaults to the episode's name.
# Example: ulam = { account = "portfolio", subdomain = "ulam", anthropic = true }
# An empty subdomain puts a portfolio episode at the zone's apex.
#
# episode-template has no entry, so it has no site, and its PRs run only rounds,
# checks and green (episode-template #65).
episodes = {
  # Episode 0: the series home and the "Ask about Emiliano" chat.
  portfolio-site = { account = "portfolio", subdomain = "", anthropic = true }
}
