# v1be-infra

The Foundation for [V1be Coding](https://github.com/v1be-coding), a build series where each app goes from spec to deployed in one agent run. This repo holds the AWS accounts, guardrails and shared infrastructure every episode relies on, all in Terraform.

## Layout

| Path | Holds |
| --- | --- |
| `stacks/org/` | The Organization, member accounts, SCPs, Identity Center, Budgets, and GitHub org settings and repos |
| `sandbox/` | The Windows Sandbox config that admin logins run in, and the step-by-step wizards |
| `.devcontainer/` | The container Claude Code works in, which holds no admin login |

## How it stays safe

- **Separate environments:** Claude writes the code in a dev container, and admin logins only exist in a disposable Windows Sandbox.
- **Service allowlists:** an SCP on each member account denies every AWS service that isn't listed.
- **Cost guards:** Budgets alerts fire at $3 forecast and $5 actual.
- **No long-lived keys:** people sign in with Identity Center, and member accounts can't create IAM users or access keys.

## Running it

`org` runs only in Windows Sandbox. Copy `sandbox/v1be-admin.wsb.example` to `sandbox/v1be-admin.wsb`, set your folder path, open it, then run `sandbox/wizards/org-apply.sh` in Git Bash.

