# Adding an episode

The Setup phase of [`V1BE_CODING.md`](https://github.com/v1be-coding/series/blob/main/V1BE_CODING.md), as `/setup` in an episode session runs it. This repo is public, so everything Setup needs is here, not in private notes.

## Who does what

| Step | Who |
| --- | --- |
| 1. A PR that adds the episode, plus any infra change it needs | Claude, as the `v1be-agent` App |
| 2. Review and merge it | The user |
| 3. Run `sandbox/wizards/org-apply.sh` in Windows Sandbox. It makes the repo from `episode-template`, with its rules, environments and variables. Then add the new repo to the `v1be-agent` App's installation | The user |
| 3a. Check the App can see the new repo | Claude |
| 3b. A PR to the episode repo with any notes the spec needs | Claude, as the `v1be-agent` App |
| 3c. A PR that adds the new repo's `repo_id` to its entry, then the user merges it | Claude, as the `v1be-agent` App |
| 4. Approve `deploy-episodes`' apply: DNS, certificate, generated secrets, the CI role | The user |
| 5. Set the episode's Anthropic workspace monthly limit and connect its Lambda in the Console, and enter any other third-party keys into SSM | The user, guided by a `wizard` |

Claude runs no `terraform plan` or `apply`, and no admin step (ADR-0012).

## 1. The PR

Work in a fresh clone from GitHub, on a new branch from `origin/main`. A local copy may be stale or on another branch.

**The entry**, in `stacks/episodes.tfvars`. Both `org` and `episodes` read it:

| Field | Meaning |
| --- | --- |
| `account` | `portfolio`, or `cafe` for the café's real backend |
| `subdomain` | The site is `<subdomain>.<zone>`. A café episode's demo is `<subdomain>-demo.<zone>`. An empty subdomain puts a portfolio episode at the zone's apex |
| `zone` | Optional. Defaults to the main zone |
| `repo` | Optional. Defaults to the episode's name |
| `repo_id` | The repo's numeric ID. Left out of this PR, as the repo doesn't exist yet. Step 3c adds it |
| `anthropic` | Optional. Set it when the app calls Anthropic |

**A new AWS service** goes on `shared_services` in `stacks/org/scp.tf`, in the same PR. Member accounts refuse anything off that list (ADR-0007).

**Any other infra change** the episode needs, such as a hostname shape the module doesn't support yet, goes in `modules/episode` or the stacks, kept generic so later episodes can use it. Say in the PR why the episode needs it.

**An edge change for production** (a function, a headers policy, a route) also needs an answer for branch environments, in the same PR. Do they need it too? If so, can CI's branch role read or build it (`modules/episode/branch.tf`)? Episode 0 missed this twice: the branch headers policy, and the clean-URL function #46 added.

**A new zone** gets every Cloudflare setting that rewrites responses pinned in `stacks/edge/cloudflare.tf` through `local.zones`. Two features stay in the dashboard, so check both in the new zone, in Sandbox. **Security → Bots → Bot Fight Mode** must be off: its JavaScript detections inject a script the CSP blocks, and it can challenge `/api/*` with no way to exempt it. **Web Analytics** must be disabled (Manage RUM settings → Disable), not deleted. A new free zone starts with it on, and its beacon broke episode 0's CSP. Cloudflare promises not to turn RUM back on once it's disabled, and doesn't say whether deleting counts. The served-HTML smoke test catches either one in production.

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

- **Step 3:** the `org` plan adds the new repo, its rules and environments, and its variables (`EPISODE`, `ACCOUNT`, `SITE_URL`). Any destroy in that plan is a reason to stop: the wizard lists it and asks you to type `destroy`, so answer anything else unless you meant to remove something.
- **Step 3, the App:** the `v1be-agent` App is installed on selected repos only, and `org` can't add one: GitHub refuses the wizard's `gh` login token for that ("You do not have permission to modify this app", 2026-11-19). So after the apply, in the Sandbox, the user opens the org's **Settings → GitHub Apps → `v1be-agent` → Configure**, adds the new repo under **Repository access**, and saves. Without it, the App's first push to the repo gets a 403, as `portfolio-site`'s did.
- **Step 3a:** Claude runs `gh api installation/repositories --jq '.repositories[].name'` in the dev container, which uses the App's token, and confirms the new repo is listed before any episode session starts.
- **Step 3b:** the spec session sees only the episode repo, not private notes. So anything Setup learned that the spec must honour goes in `docs/agents/setup-notes.md` in the episode repo, through a PR the user merges before the spec phase. Examples: an infra limit found in step 1 (something CI's role can't build), a service or hostname the PR added, a third-party limit set in step 5. The template's `docs/agents/spec.md` tells the spec session to read it. Skip the PR when there's nothing to say. Before episode 0 had this, its notes were pasted into `/grill-with-docs` by hand.
- **Step 3c:** Claude reads the ID with `gh api repos/v1be-coding/<repo> --jq .id` and opens a one-line PR adding `repo_id = <id>` to the entry. The CI role trusts the repo by name and this ID, so a wrong number refuses the repo's CI rather than trusting another repo. The ID is in tfvars, not looked up, because an unauthenticated GitHub lookup hung two applies until they timed out (2026-11-19 and 2026-11-20).
- **Step 4:** the `deploy-episodes` run step 2's merge starts fails at `plan`, on the validation that asks for `repo_id`. That's expected. Step 3c's merge starts a new run, and its apply waits for approval. For the first episode in `portfolio`, the plan also creates `aws_budgets_budget_action.portfolio[0]`, the spend guard, which exists only while an episode does. Each later `portfolio` episode changes that action and its role policy in place, 2 changes, because the action covers every episode's CI role.
- **Step 5:** each key goes straight into SSM at `/<episode>/third-party/<name>` as a SecureString, from the admin login. A key never passes through chat or a transcript.
- **Step 5, Anthropic:** no key. The Lambda proves its role to Anthropic with a short-lived AWS token (workload identity federation).
  1. The first episode with `anthropic = true` needs the `accounts` stack applied in `portfolio`. That turns on the account's token issuer, and its `token_issuer` output is the URL Anthropic asks for.
  2. Run `sandbox/wizards/anthropic-workload.sh <episode>` in Windows Sandbox. It covers the rest:
     - It checks that STS in Singapore issues an Anthropic token.
     - It has the user turn off auto-reload, and give the episode its own workspace with a monthly limit ($30 for `portfolio-site`). The default workspace can't have a limit.
     - It runs **Connect workload** with the AWS tile, with the rule's subject `arn:aws:iam::<account>:role/v1be-<episode>-api-*`. That covers production and every branch environment (`…-api-pr-<n>`), so a frozen test can call the real model on a branch. Never use `role/*`, which trusts every role in the account.
  3. The wizard saves the organization, workspace, service account and rule IDs as JSON in the String parameter `/<episode>/third-party/anthropic-federation`, and the Lambda reads that at cold start. They're IDs, not secrets, but they stay out of the public repos.
  4. Leave `ANTHROPIC_API_KEY` unset. The SDK prefers it over federation.

  If federation fails, fall back to a service account key in SSM, as above.

## Rules

- No account IDs, personal email addresses or the sign-in portal URL in this repo or its PRs. It's public, and so are its Actions logs.
- No real data in any public repo. The café's real data stays in its own account.
- Removing an episode is a separate, admin-run job. Its production stays behind when its entry goes, so ask the user instead.
