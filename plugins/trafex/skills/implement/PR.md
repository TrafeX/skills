# Pull request

Every PR body is written by following `<upstream>/pr/SKILL.md` (Summary, Evidence, Merge Danger), using the glossary's terms, followed by a line naming the issues it closes:

```markdown
<body from the pr skill>

Closes #<issue>
```

Leave out the `Closes` line when there is no issue. The PR title follows the commit subject rule in the conventions the settings name.

## Look at the change first

Before the title and body, ask the developer whether they want to look at the change first, or open the PR now. Do not name a phone or a preview in that question. When they want to look at it, ask a second question: locally, in their own checkout where their dev server runs, or via Tailscale, for example on their phone?

### Via Tailscale

Read `../preview/SKILL.md`, relative to this skill's base directory, and follow it to start a preview of `<branch>`'s worktree. Fixes they ask for go on `<branch>` in that worktree, each as its own commit, followed by the settings' full checks; on the large route, push them (`git push <remote> <branch>`). Once they are done looking, stop the preview with `stop --purge` and continue below.

### Locally

1. Git refuses to check out a branch that another worktree holds, so free it: when `git -C <worktree> status --porcelain` is empty, `git worktree remove <worktree>` (the commits stay on the branch). Run that from `<root>`, not from inside the worktree. With uncommitted changes, stop and ask: they belong in a commit first.
2. Tell the developer to run `git -C <root> switch <branch>` themselves, plus the settings' install command when the change touches dependencies. Do not switch their checkout for them: it may hold work of their own.
3. Wait until they report back. Fixes they ask for go on `<branch>` in their checkout, each as its own commit, followed by the settings' full checks; this is the only time the flow works outside a worktree. On the large route, push them (`git push <remote> <branch>`), since the draft PR already tracks the branch.
4. Then continue below. Push and PR commands work from `<root>`, since the branch is a ref the checkouts share.

## Open the PR

When the developer chose to open the PR, or asks for one, that is the approval: open it straight away, without first showing the title and body.

- Small route: `git push -u <remote> <branch>`, then `gh pr create --base <base> --head <branch> --title "<title>" --body-file <file>`.
- Large route: update the draft PR and mark it ready, as in [LARGE.md](LARGE.md) step 8.

Report the PR's URL; they read the title and body there.
