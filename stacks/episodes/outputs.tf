output "ci_roles" {
  description = "Each episode's CI role name, by account."
  value = {
    portfolio = { for name, episode in module.portfolio : name => episode.ci_role_name }
    cafe      = { for name, episode in module.cafe : name => episode.ci_role_name }
  }
}
