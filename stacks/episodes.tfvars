# Every episode in the series. `org` makes each one's repo from the template,
# and `episodes` builds its AWS side. `zone` is optional and defaults to the main zone.
# `repo` is optional and defaults to the episode's name.
# Example: ulam = { account = "portfolio", subdomain = "ulam", anthropic = true }
#
# Empty since phase F: smoke-test (the template deploying itself) and phase-f
# were removed. Without an entry, episode-template has no site, and its PRs run
# only rounds, checks and green (episode-template #65).
episodes = {}
