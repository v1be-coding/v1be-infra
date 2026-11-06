# Every episode in the series. `zone` is optional and defaults to the main zone.
# `repo` is optional and defaults to the episode's name.
# Example: ulam = { account = "portfolio", subdomain = "ulam", anthropic = true }
episodes = {
  # The template proves itself, so its slices need no copy. Phase F moves this to
  # a repo made from the template.
  smoke-test = { account = "portfolio", subdomain = "smoke-test", repo = "episode-template" }
}
