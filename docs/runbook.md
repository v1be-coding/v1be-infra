# Runbook

What to do when something goes wrong. Admin, GitHub owner and Cloudflare logins still happen only in Windows Sandbox, unless the PC is gone.

## Locked out of an account

| What's lost | Way back in |
| --- | --- |
| Your phone | Use the second MFA device for AWS, or the recovery codes in your password manager for everything else. Then replace the lost device on each account |
| `v1be-admin` | Sign in as root to the management account, and fix the user in IAM Identity Center. Its management account access is left out of Terraform so a bad run can't remove it |
| AWS root MFA | Use the second device. If both are gone, use AWS's sign-in recovery, which checks the root email and phone number |
| Your password manager | Use its recovery kit, kept outside the vault |
| Gmail | Use its backup codes. Every other password reset depends on this account, so fix it first |

## Lost or stolen laptop

The dev container's volumes hold `v1be-bot`'s token and the `claude-readonly` session. Neither is an admin login, but treat both as exposed. From another device:

1. Change your Gmail password and sign out of other sessions.
2. Change your password manager's master password.
3. In GitHub, revoke `v1be-bot`'s token, and sign out your own sessions.
4. In IAM Identity Center, revoke the sessions of `v1be-admin` and `claude-readonly`.
5. Roll the Cloudflare token and update it on the `plan` and `apply` environments.
6. Sign out of Anthropic, and check for API keys you don't recognise.
7. Check CloudTrail and the GitHub audit log for anything you didn't do.

## The Budgets action fired

The action attaches a deny-all policy to every portfolio episode's CI role, so deploys stop. Anything already running keeps costing money.

**Never detach the policy by hand.** Budgets wouldn't know, so the action may not fire again that month. Reverse it, then reset it:

```bash
aws budgets execute-budget-action --account-id <id> --budget-name <name> \
  --action-id <id> --execution-type REVERSE_BUDGET_ACTION

aws budgets execute-budget-action --account-id <id> --budget-name <name> \
  --action-id <id> --execution-type RESET_BUDGET_ACTION
```

Fix the cause first. The policy probably lifts by itself at the start of the next budget period, even if nothing was fixed.

If someone has already detached it, run the same two commands and check the action's status. Phase F tests this path, so update this section with what really happens.

## Nothing can merge in `v1be-infra`

`main` requires the `risky-text` check, even for the owner. A broken `ci/check-pr-text.sh` or workflow, or a GitHub Actions outage, can stop every PR, including the fix. The check runs `main`'s copy, so a PR can't repair it by itself.

In the Sandbox, as owner:

1. Open the repo's branch settings and edit the `main` rule.
2. Untick **Do not allow bypassing the above settings**, and save.
3. Merge the fix.
4. Run `sandbox/wizards/org-apply.sh`, which puts the rule back. The plan shows the rule being restored.

## Renewing tokens

| Token | Lasts | To renew |
| --- | --- | --- |
| `v1be-bot` | 90 days | Create a new one, get it approved in the org, then run `.devcontainer/bot-identity.sh` |
| `v1be-infra-edge` (Cloudflare) | One year | Roll it, then update the `plan` and `apply` environments |
