---
name: triage
description: Weekly triage of open Dependabot PRs across all your GitHub repos. Fetches every open Dependabot PR, inventories the changes (expanding grouped updates), classifies them by risk tier, presents a summary, then lets you mass-merge or mass-ignore whole groups — gating merges on green CI. Use when the user wants to review/merge/ignore Dependabot dependency-update PRs, do a dependency-update sweep, or "check my Dependabot PRs".
---

# Dependabot triage

A repeatable routine for reviewing open Dependabot PRs across all of a user's
repos, then mass-merging or mass-ignoring them in risk-based batches.

Prerequisite: the `gh` CLI must be installed and authenticated (`gh auth status`).
The default GitHub owner is whatever `gh api user --jq .login` returns; ask the
user if they want a different org/owner.

## Environment gotchas (read first)

- **zsh does not word-split unquoted variables** (unlike bash). Do NOT rely on
  `for x in "a 1"; do set -- $x; ...`. Use a shell function with explicit
  positional args, or `${x% *}` / `${x##* }` parameter expansion. Every loop in
  this skill uses functions to avoid this.
- **`sudo` cannot authenticate** in the non-interactive tool shell. If any setup
  needs root, give the user the command to run themselves via `!` in the prompt.
- **`workflow` OAuth scope**: merging a PR that edits a `.github/workflows/*`
  file fails with `refusing to allow an OAuth App ... without workflow scope`.
  Fix: have the user run `! gh auth refresh -h github.com -s workflow`, then retry.

## Step 1 — Fetch all open Dependabot PRs

```sh
OWNER=$(gh api user --jq .login)          # or an org the user names
gh search prs --author "app/dependabot" --owner "$OWNER" --state open --archived=false \
  --limit 200 --json repository,number,title,url,createdAt
```

`--archived=false` is essential: an archived repo is read-only, so its Dependabot
PRs can be neither merged nor closed — not even by Dependabot itself. They linger
in search results forever and are pure triage noise. Note that the `repository`
JSON field only carries `name`/`nameWithOwner`, so there is no `isArchived` to
filter on after the fact — you must use the flag.

## Step 2 — Expand grouped PRs

Grouped PRs have titles like *"Bump the npm-updates group ... with N updates"* and
hide the individual bumps. There are two body shapes:

- **Single-directory groups**: the body contains a `| Package | From | To |`
  markdown table. Parse it:
  ```sh
  gh pr view "$NUM" --repo "$REPO" --json body --jq '.body' \
    | grep -E '^\| \[' \
    | sed -E 's/\[([^]]+)\]\([^)]*\)/\1/g; s/`//g; s/^\| //; s/ \| / : /g; s/ \|$//'
  ```
- **"across N directories" groups**: the body does NOT contain the table. Instead
  read the manifest diff (skip lock files):
  ```sh
  gh pr diff "$NUM" --repo "$REPO" \
    | awk '/^diff --git.*package\.json/{f=($0 !~ /package-lock/)} f&&/^[+-] *"/{print}' \
    | grep -E '^[+-] *"' | grep -vE 'resolved|integrity|"version"|"name"'
  ```
  (For non-npm ecosystems, diff the relevant manifest: `go.mod`, `Gemfile`,
  `requirements.txt`, `pom.xml`, Dockerfile, etc.)

The goal of expansion is to detect **major-version bumps hidden inside a group** so
they aren't silently mass-merged as "safe".

## Step 3 — Classify into tiers

Judge each bump by semver delta (major = leftmost non-zero component changes; for
`0.x`, a change in the first non-zero component is breaking):

- **Tier 1 — Safe**: minor/patch of libraries; CI action bumps
  (`actions/*`, `docker/*`, `github/*`); patch/minor of base images. Low risk.
  - Flag base-image bumps for **published** images (e.g. a `docker-*` repo) — a
    minor bump can still break downstream users; call it out even in Tier 1.
- **Tier 2 — Runtime / types majors**: base-image major (e.g. `node 24→25`),
  `@types/node` majors. Usually fine but want green CI.
- **Tier 3 — Library majors**: application-dependency major bumps (breaking-change
  risk). Never mass-merge; summarize changelogs on request.
- **Tier 4 — Stale**: PRs older than ~6 months (often dead repos), but note any
  that are security/CVE fixes.

Present as a markdown table grouped by tier: repo, PR link, the update(s), and a
one-line note. Give a recommendation (usually: merge Tier 1, decide 2–4 per-PR).

## Step 4 — Let the user choose

Use AskUserQuestion with multiSelect for the merge batch (Tier 1 / Tier 2 /
Tier 4 / none) and a separate question for how to handle majors (leave open /
summarize changelogs / ignore major versions). Never merge without an explicit pick.

## Step 5 — Gate on CI, then act

**Before merging**, check each chosen PR and skip any with a failing/pending check.
Re-poll `mergeable` once if it comes back `UNKNOWN` (GitHub computes it lazily):

```sh
gh pr view "$NUM" --repo "$REPO" --json number,mergeable,mergeStateStatus,statusCheckRollup \
  --jq '.mergeStateStatus, ([.statusCheckRollup[]?|.conclusion//.state]|join(","))'
```
- `CLEAN` / all checks `SUCCESS` (or `none`) → safe to merge.
- `UNSTABLE` or any `FAILURE` → **skip**, report it, offer to investigate (Step 6).
- `BEHIND` (base moved on, branch protection wants it up to date) or `DIRTY`
  (merge conflict) → don't skip silently: have Dependabot rebase it (Step 5a).
  This happens often after you merge one PR and a sibling PR in the same repo
  falls behind or conflicts on the lock file.

**Merge** (Dependabot branches are single-commit; try squash, fall back):
```sh
merge_pr() {  # merge_pr <repo> <num>
  for m in --squash --merge --rebase; do
    gh pr merge "$2" --repo "$1" $m --delete-branch 2>/dev/null && { echo "✅ $1 #$2 ($m)"; return; }
  done
  echo "⚠️  $1 #$2 failed (check: workflow scope? branch protection?)"
}
```

**Ignore** a bump — pick the right command based on user intent:
- `@dependabot ignore this major version` — closes THIS PR and blocks re-opening
  this specific major (e.g. drops 24→25 but still allows a future 26). Use this
  for "ignore the 24→25 upgrade".
- `@dependabot ignore <dep> major version` — blocks ALL future majors of that dep.
- `@dependabot ignore this minor version` / `... <dep> minor version` — minor equivalents.
- `@dependabot close` — just close without any ignore rule.

Post via `gh pr comment "$NUM" --repo "$REPO" --body "@dependabot ..."`.

## Step 5a — Rebase, wait for it, wait for CI, then ask

Never push to a Dependabot branch yourself: Dependabot stops updating a PR once
someone else commits to it. Let Dependabot do the rebase, and don't leave the
user to check back on it — watch it until there is a verdict.

1. **Record the current head**, then ask for the rebase:
   ```sh
   OLD=$(gh pr view "$NUM" --repo "$REPO" --json headRefOid --jq .headRefOid)
   gh pr comment "$NUM" --repo "$REPO" --body "@dependabot rebase"
   ```
   (Use `@dependabot recreate` instead only when the user agrees to drop edits
   someone else made to the branch — Dependabot refuses to rebase those.)
   Dependabot also rebases on its own after a sibling merge sometimes; then skip
   the comment and just watch with the current head as `OLD`.

2. **Watch it in the background.** Run this with `run_in_background` (one call
   per PR, so several rebases run side by side); the harness wakes you when it
   exits, so do not poll in between. Carry on with the rest of the batch meanwhile.
   ```sh
   await_rebase() {  # await_rebase <repo> <num> <old-head-sha>
     local deadline=$(( $(date +%s) + 1800 )) state sha
     while :; do  # 1. wait until Dependabot has pushed a new head
       read -r state sha <<<"$(gh pr view "$2" --repo "$1" --json state,headRefOid \
         --jq '"\(.state) \(.headRefOid)"')"
       [[ $state != OPEN ]] && { echo "STOPPED $1 #$2 is $state"; return 1; }
       [[ $sha != "$3" ]] && break
       (( $(date +%s) > deadline )) && { echo "TIMEOUT $1 #$2 not rebased in 30 min"; return 2; }
       sleep 30
     done
     sleep 30  # 2. give the workflows time to register on the new head
     gh pr checks "$2" --repo "$1" --watch --interval 30 >/dev/null 2>&1
     gh pr view "$2" --repo "$1" --json mergeStateStatus,statusCheckRollup \
       --jq '"DONE '"$1 #$2"' \(.mergeStateStatus) " + ([.statusCheckRollup[]?|.conclusion//.state]|join(","))'
   }
   ```
   - `STOPPED` → the PR was closed or merged meanwhile (often superseded by a
     newer Dependabot PR); report it, nothing left to do.
   - `TIMEOUT` → read Dependabot's last comment on the PR
     (`gh pr view "$NUM" --repo "$REPO" --comments`) to see why it didn't
     rebase, and report that.
   - `DONE` → the rebase landed and CI has finished; go to 3.

3. **Ask the user what to do**, per PR, with AskUserQuestion. Put the PR, the
   update and the CI outcome in the question itself. Options:
   - green (`CLEAN`, all `SUCCESS`): **Merge (Recommended)** / Ignore / Leave open
   - red: **Investigate the failure (Recommended)** (Step 6) / Ignore / Leave open
   - still `BEHIND`/`DIRTY` (base moved again during the wait): Rebase again /
     Leave open

   Merge with `merge_pr`, ignore with the commands below. Don't merge on a
   verdict from before the rebase: only the `DONE` line counts.

## Step 6 — (Optional) Investigate a red CI failure

```sh
gh pr checks "$NUM" --repo "$REPO"                       # find the failing job URL
gh run view --repo "$REPO" --job "$JOB_ID" --log-failed  # read the failing step
```
Report the root cause and whether the bump itself caused it (e.g. a `prettier`
minor reformatting files, or a base-image bump moving a binary path). Offer to push
a fix, but don't push without the user's go-ahead.

## Final report

Summarize: merged (with count), ignored/closed, rebased (with outcome), skipped-for-CI
(with reason), and what was left open per the user's choices.
