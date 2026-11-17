# Adding an episode

The Setup phase of [`V1BE_CODING.md`](https://github.com/v1be-coding/series/blob/main/V1BE_CODING.md), as `/setup` in an episode session runs it. This repo is public, so everything Setup needs is here, not in private notes.

## Who does what

| Step | Who |
| --- | --- |
| 1. A PR that adds the episode, plus any infra change it needs | Claude, as the `v1be-agent` App |
| 2. Review and merge it | The user |
| 3. Run `sandbox/wizards/org-apply.sh` in Windows Sandbox. It makes the repo from `episode-template`, with its rules, environments and variables | The user |
| 4. Approve `deploy-episodes`' apply: DNS, certificate, generated secrets, the CI role | The user |
| 5. Set the episode's Anthropic workspace monthly limit in the Console, and enter third-party keys into SSM | The user, guided by a `wizard` |

Claude runs no `terraform plan` or `apply`, and no admin step (ADR-0012).

## 1. The PR

Work in a fresh clone from GitHub, on a new branch from `origin/main`. A local copy may be stale or on another branch.

**The entry**, in `stacks/episodes.tfvars`. Both `org` and `episodes` read it:

| Field | Meaning |
| --- | --- |
| `account` | `portfolio`, or `cafe` for the café's real backend |
| `subdomain` | The site is `<subdomain>.<zone>`. A café episode's demo is `<subdomain>-demo.<zone>` |
| `zone` | Optional. Defaults to the main zone |
| `repo` | Optional. Defaults to the episode's name |
| `anthropic` | Optional. Set it when the app calls Anthropic |

**A new AWS service** goes on `shared_services` in `stacks/org/scp.tf`, in the same PR. Member accounts refuse anything off that list (ADR-0007).

**Any other infra change** the episode needs, such as a hostname shape the module doesn't support yet, goes in `modules/episode` or the stacks, kept generic so later episodes can use it. Say in the PR why the episode needs it.

**Checks before opening the PR.** CI runs the same ones, but only after the push:

```bash
terraform fmt -check -recursive
for s in stacks/*/; do terraform -chdir="$s" init -backend=false -lockfile=readonly -input=false && terraform -chdir="$s" validate; done
tflint --recursive
bash ci/check-provider-aliases.sh stacks
```

**The PR body** says what the user will see in step 3's `org` plan and step 4's `deploy-episodes` plan, so they can check each plan against it: which repo, which hostname, and which new resources.

## 2 to 5. The user's steps

Write them up with the `wizard` skill, one step at a time, and check each result before the next.

- **Step 3:** the `org` plan adds the new repo, its rules and environments, and its variables (`EPISODE`, `ACCOUNT`, `SITE_URL`). Any destroy in that plan is a reason to stop.
- **Step 4:** `deploy-episodes` runs when the PR merges, and its apply waits for approval. For the first episode in `portfolio`, the plan also creates `aws_budgets_budget_action.portfolio[0]`, the spend guard, which exists only while an episode does.
- **Step 5:** each key goes straight into SSM at `/<episode>/third-party/<name>` as a SecureString, from the admin login. A key never passes through chat or a transcript.

## Rules

- No account IDs, personal email addresses or the sign-in portal URL in this repo or its PRs. It's public, and so are its Actions logs.
- No real data in any public repo. The café's real data stays in its own account.
- Removing an episode is a separate, admin-run job. Its production stays behind when its entry goes, so ask the user instead.
