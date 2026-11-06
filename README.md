# v1be-infra

The Foundation for [V1be Coding](https://github.com/v1be-coding), a build series where each app goes from spec to deployed in one agent run. This repo holds the AWS accounts, guardrails and shared infrastructure every episode relies on, all in Terraform.

## Layout

| Path | Holds |
| --- | --- |
| `stacks/org/` | The Organization, member accounts, SCPs, Identity Center, Budgets, and GitHub org settings and repos |
| `stacks/accounts/` | Once per member account: state buckets, GitHub OIDC login, CI roles, Cost Anomaly Detection, and the café backups |
| `stacks/edge/` | CI runs this for each Cloudflare zone: Full (strict), the origin header, the cache bypass and the rate limit. In each member account, the header-check function and what it needs |
| `modules/` | Pieces the stacks share |
| `sandbox/` | The Windows Sandbox config that admin logins run in, and the step-by-step wizards |
| `.devcontainer/` | The container Claude Code works in, which holds no admin login |

## How it stays safe

- **Separate environments:** Claude writes the code in a dev container, and admin logins only exist in a disposable Windows Sandbox.
- **Service allowlists:** an SCP on each member account denies every AWS service that isn't listed.
- **Cost guards:** Budgets alerts fire at $3 forecast and $5 actual.
- **No long-lived keys:** people sign in with Identity Center, and member accounts can't create IAM users or access keys.

## Running it

`org` and `accounts` run only in Windows Sandbox. Copy `sandbox/v1be-admin.wsb.example` to `sandbox/v1be-admin.wsb`, set your folder path, and open it. In Git Bash, run `sandbox/wizards/org-apply.sh` for `org`, or `sandbox/wizards/accounts-apply.sh portfolio` and then `cafe` for `accounts`.

`sandbox/wizards/github-template-access.sh` gives the bot's token Issues access and saves the Infracost key as an organization secret, once, before `org-apply.sh` adds the template's rules.

`edge` runs in GitHub Actions after a merge, once the owner approves the apply. `sandbox/wizards/edge-setup.sh` sets it up the first time.
