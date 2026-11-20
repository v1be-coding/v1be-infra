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

The dev container's volumes hold the `v1be-agent` App's private key and the `claude-readonly` session. Neither is an admin login, but treat both as exposed. From another device:

1. Change your Gmail password and sign out of other sessions.
2. Change your password manager's master password.
3. In GitHub, delete the `v1be-agent` App's private key, and sign out your own sessions.
4. In IAM Identity Center, revoke the sessions of `v1be-admin` and `claude-readonly`.
5. Roll the Cloudflare token and update it on the `plan` and `apply` environments.
6. Sign out of Anthropic, and check for API keys you don't recognise.
7. Check CloudTrail and the GitHub audit log for anything you didn't do.

## The Budgets action fired

The action attaches `AWSDenyAll` to every portfolio episode's CI role, so deploys stop, and `v1be-alerts` emails you. Anything already running keeps costing money.

It acts fast. In phase F, lowering the limit below the month's spend fired it within minutes, though Budgets only promises to check up to three times a day.

**Never detach the policy by hand.** Budgets wouldn't know, so the action may not fire again that month. As the admin login in `portfolio`, fix the cause, then reverse it. The budget is `v1be-portfolio-monthly`, and this shows the action's ID and status:

```bash
aws budgets describe-budget-actions-for-budget --account-id <id> \
  --budget-name v1be-portfolio-monthly --query "Actions[].[ActionId,Status]"
```

`EXECUTION_SUCCESS` means it's on. Reverse it:

```bash
aws budgets execute-budget-action --account-id <id> --budget-name v1be-portfolio-monthly \
  --action-id <id> --execution-type REVERSE_BUDGET_ACTION
```

Then read the status again:

- **`STANDBY`:** done. It's armed again. Phase F's reverse ended here, with spend back under the limit, and a reset was then refused with `ResourceLockedException ... [ActionStatus: Standby]`.
- **`REVERSE_SUCCESS`:** reset it, so it's armed for the next overrun. If spend is still over the limit, it may fire again straight away.

```bash
aws budgets execute-budget-action --account-id <id> --budget-name v1be-portfolio-monthly \
  --action-id <id> --execution-type RESET_BUDGET_ACTION
```

The policy probably lifts by itself at the start of the next budget period, even if nothing was fixed.

Untested: what happens if someone has already detached the policy. Read the status, and follow the same steps.

Afterwards, look for a stale state lock (below). A deploy that was applying when the action fired couldn't release its lock (phase F).

## A stale state lock

Every Terraform run in CI fails with `Error acquiring the state lock`, or a failed run's `Name a stale state lock` step names one. Terraform keeps the lock as a `.tflock` file next to the state, and a run that was killed or refused mid-apply leaves it behind. Each run has a timeout that stops Terraform cleanly first, so this should be rare. A deny-all or an expired sign-in can still strand one.

1. Make sure no run is using that state: no `deploy`, `deploy-episodes` or `teardown` run in progress for it on GitHub. Deleting a live run's lock lets two runs write the same state.
2. As the admin login in the account that holds the bucket, list the locks. `v1be-infra-state` and `v1be-portfolio-state` are in `portfolio`, and `v1be-cafe-state` in the café:

   ```bash
   aws s3 ls s3://v1be-portfolio-state --recursive | grep '\.tflock$'
   ```

3. Delete the one the error names, then rerun the failed run:

   ```bash
   aws s3 rm s3://v1be-portfolio-state/<episode>/production/terraform.tfstate.tflock
   ```

## Nothing can merge in `v1be-infra`

`main` requires the `risky-text` check, even for the owner. A broken `ci/check-pr-text.sh` or workflow, or a GitHub Actions outage, can stop every PR, including the fix. The check runs `main`'s copy, so a PR can't repair it by itself.

In the Sandbox, as owner:

1. Open the repo's branch settings and edit the `main` rule.
2. Untick **Do not allow bypassing the above settings**, and save.
3. Merge the fix.
4. Run `sandbox/wizards/org-apply.sh`, which puts the rule back. The plan shows the rule being restored.

## Removing an episode

An episode has two halves, and removing it from `episodes.tfvars` removes only `v1be-infra`'s. The episode's own Terraform made its database, Lambda, limits table, alarms and logs, and nothing removes those once its CI role is gone. So remove production first, while the API and secret that `v1be-infra` made still exist: the episode's Terraform reads them.

1. **Close every PR,** so no branch environment is left. Each PR's teardown removes its environment. No `<episode>/pr-*` state should remain in the account's state bucket.
2. **Destroy the episode's production, in Windows Sandbox as admin.** Turn off the DSQL cluster's deletion protection, which Terraform can't do. Then, from a clone of the episode repo, run `terraform -chdir=infra destroy` against the state at `<episode>/production/terraform.tfstate`, with the variables its `deploy-target.yml` sets and `environment=production`. Check that every line names the episode before typing `yes`, then delete the empty state file. Phase F did this with `phase-f-checks.sh destroy`, a local draft. Turn that into a wizard the next time an episode is removed.
3. **A PR removing the entry from `episodes.tfvars`.** `deploy-episodes`' plan destroys the CI role, distribution, DNS, certificate and generated secrets. Check that every destroy names this episode. If it was the last `portfolio` episode, the Budgets action goes too.
4. **Run `org-apply.sh` in Windows Sandbox.** It archives the repo (`archive_on_destroy`), keeping its history, and removes the repo's rules, environments and variables. Then remove the repo from the `v1be-agent` App's installation.

## Removing a provider, a data source or a resource from state

Two traps, both from `v1be-infra` #62 to #65 (2026-11-20):

- **`init` needs a provider while state still names its resources,** data sources included. CI runs `init -lockfile=readonly`, so dropping the provider and the resources in one PR fails at `init`. The checks in `adding-an-episode.md` run `init -backend=false`, which has no state, so they can't catch it. Remove the resources first and keep the provider in `required_providers` and the lock, with no `provider` block. Then remove the provider in a second PR.
- **`deploy-episodes` applies only when the plan has changes.** A removed data source, or a `moved` or `removed` block on its own, changes state but not the plan, so the apply is skipped and state keeps the old entries. Land it with a real change. If there's none, add an empty `terraform_data` resource, as #64 did, and remove it in the next PR.

## Renewing tokens

| Token | Lasts | To renew |
| --- | --- | --- |
| `v1be-agent` private key | Never expires, so rotate every 90 days | In Windows Sandbox, generate a new one on the App's page. Run `.devcontainer/bot-identity.sh`, then delete the old key |
| `v1be-infra-edge` (Cloudflare) | One year | Roll it, then update the `plan` and `apply` environments |
