# Pull request

Every PR body is written by following `<upstream>/pr/SKILL.md` (Summary, Evidence, Merge Danger), using the glossary's terms, followed by a line naming the issues it closes:

```markdown
<body from the pr skill>

Closes #<issue>
```

Leave out the `Closes` line when there is no issue. The PR title follows the commit subject rule in the conventions the settings name.

## Test locally first

Before the title and body, ask the developer: open the PR now, or check out the branch in their own checkout first to test it by hand?

When they want to test it:

1. Git refuses to check out a branch that another worktree holds, so free it: when `git -C <worktree> status --porcelain` is empty, `git worktree remove <worktree>` (the commits stay on the branch). Run that from `<root>`, not from inside the worktree. With uncommitted changes, stop and ask: they belong in a commit first.
2. Tell the developer to run `git -C <root> switch <branch>` themselves, plus the settings' install command when the change touches dependencies. Do not switch their checkout for them: it may hold work of their own.
3. Wait until they report back. Fixes they ask for go on `<branch>` in their checkout, each as its own commit, followed by the settings' full checks; this is the only time the flow works outside a worktree. On the large route, push them (`git push <remote> <branch>`), since the draft PR already tracks the branch.
4. Then continue below. Push and PR commands work from `<root>`, since the branch is a ref the checkouts share.

## Open the PR

**Show the title and body to the developer before anything leaves the machine.** Only after they approve:

- Small route: `git push -u <remote> <branch>`, then `gh pr create --base <base> --head <branch> --title "<title>" --body-file <file>`.
- Large route: update the draft PR and mark it ready, as in [LARGE.md](LARGE.md) step 8.

Report the PR's URL.
