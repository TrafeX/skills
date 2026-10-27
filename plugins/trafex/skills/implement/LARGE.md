# Large route

Three upstream skills in order, all read from `<upstream>/<name>/SKILL.md` and followed: `to-spec`, `to-tickets`, then `implement-spec`. Pick a `<topic>` for the change (one word, like `review` or `refinement`); branch names below use it. `<remote>` and `<base>` are as in [SKILL.md](SKILL.md) step 1.

## 1. Spec

Follow `to-spec` with these deviations:

- **`to-spec`, step 2 (the seams):** prefer the seams the settings point to. The seams the developer confirms go into the spec's Testing Decisions, so ticket subagents can work from them without asking.
- **`to-spec`, step 3 (publish):** the spec is an issue in the repo's tracker (`docs/agents/issue-tracker.md`). When the developer passed an issue to start from, ask whether to publish a new spec issue or rewrite that one as the spec.

## 2. Tickets

Follow `to-tickets` with this deviation:

- **`to-tickets`, step 5 (publish):** every ticket is a sub-issue of the spec issue, and blocking edges are the tracker's native issue dependencies, both as described in `docs/agents/issue-tracker.md`.

## 3. Implement

Follow `implement-spec` with these deviations:

- **`implement-spec`, step 3 (integration branch):** the worktree opened in [SKILL.md](SKILL.md) step 2 becomes the integration branch: rename its branch to `<topic>/integration` (`git branch -m`), commit the grilling's glossary and ADR changes as its first commit (when the grilling changed no docs, there is no such commit and the first ticket merge comes first), and push it (`git push -u <remote> <topic>/integration`) before any ticket starts, so the ticket subagents build on the new language. The draft PR goes from `<topic>/integration` to `<base>` after the first merge in step 5; its body closes the spec and every ticket (`Closes #<n>` for each). The body is a placeholder until step 8.
- **`implement-spec`, step 4 (implementer subagents):** each ticket gets its own worktree, `<root>/.claude/worktrees/<topic>-<issue>` (`<root>` as in [SKILL.md](SKILL.md) step 1), on branch `<topic>/<issue>-<slug>`, created from `<topic>/integration`. The implementer subagent's brief, besides pointers to the spec issue and its ticket:
  - work from the seams in the spec's Testing Decisions; do not ask the developer to confirm them;
  - read `<upstream>/tdd/SKILL.md` (as an absolute path) and follow it;
  - run the settings' typecheck and its own test files (the one-test-file command), not the full checks;
  - do not run `code-review` or any other review;
  - when it meets a domain term that is not in the glossary, or the ticket conflicts with an ADR, stop and report it instead of deciding: that decision is the developer's;
  - commit as in the conventions the settings name.
- **`implement-spec`, step 5 (merge):** the merger subagent merges each finished ticket with `git merge --no-ff -m "Merge #<issue>: <ticket title>" <topic>/<issue>-<slug>` and pushes the integration branch. When a subagent stopped on a term or ADR conflict, put it to the developer first; update the glossary or ADR on the integration branch, then let the ticket continue.
- **`implement-spec`, step 7 (review):** first run the settings' full checks on the integration branch. Then run the code review in [REVIEW.md](REVIEW.md) instead of `code-review`, and put its findings to the developer before anything is fixed. Only the findings the developer chose go to the single fix subagent, which works on `<topic>/integration` and commits each fix separately.
- **`implement-spec`, step 8 (mark ready):** offer the local test in [PR.md](PR.md) for `<topic>/integration` (its worktree is the one from [SKILL.md](SKILL.md) step 2). Then write the PR body as in [PR.md](PR.md), show it to the developer, and only after they approve it: `gh pr edit <n> --body-file <file>` and `gh pr ready <n>`.
- **`implement-spec`, step 9 (clean up):** also delete the merged ticket branches (`git branch -d`).
