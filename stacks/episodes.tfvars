# Every episode in the series. `org` makes each one's repo from the template,
# and `episodes` builds its AWS side. `zone` is optional and defaults to the main zone.
# `repo` is optional and defaults to the episode's name.
# Example: ulam = { account = "portfolio", subdomain = "ulam", anthropic = true }
episodes = {
  # The template proves itself, so its slices need no copy. Whether it still
  # does after phase F is decided at the end of phase F.
  smoke-test = { account = "portfolio", subdomain = "smoke-test", repo = "episode-template" }

  # Phase F's throwaway, removed once its checks pass.
  phase-f = { account = "portfolio", subdomain = "phase-f" }
}
