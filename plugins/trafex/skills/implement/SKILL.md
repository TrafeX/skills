---
name: implement
description: "The starting point for any change to a repo, small or large: code, docs, ADRs or prompt text. Opens a fresh worktree off the base branch, grills the change while updating the glossary and ADRs, classifies it small or large, builds it test-first, runs a code review on three axes and opens a PR written with the pr skill. Use whenever the developer asks to change, fix, add or build something in a repo that uses this way of working, or passes an issue to implement, even without naming this skill."
---

# implement

One way of working for every change to a repo. It chains Matt Pocock's skills, vendored unchanged in this plugin's `upstream/mattpocock/` (see the repo's `README.md`), and holds all of our deviations from them. Each deviation names the upstream skill and step it overrides; the upstream files themselves are never edited.

**Upstream skills.** `<upstream>` is `../../upstream/mattpocock`, relative to this skill's base directory. Every upstream skill is read from `<upstream>/<name>/SKILL.md` and followed, never invoked with the Skill tool: that way the version pinned in this plugin is the one used, not a project copy or the `mattpocock-skills` plugin. Where an upstream skill says to call the Skill tool with a name, read `<upstream>/<name>/SKILL.md` instead. A sub-agent that has to follow an upstream skill gets its absolute path in its brief.

**Project settings.** Everything that differs per repo lives in the repo's `docs/agents/implement.md`; this skill calls it _the settings_. Read it before step 1. When it is missing, see [SETTINGS.md](SETTINGS.md).

**Vocabulary.** When the repo has a glossary (the settings name it), use its terms in everything you write, and follow the vocabulary notes in the settings. "Spec" and "ticket" here are issues in the repo's issue tracker, as in the upstream skills. The way of working itself adds no terms to the glossary.

## 1. Clean up merged worktrees

Worktrees live under `<root>/.claude/worktrees/`, where `<root>` is the main checkout: `dirname "$(git rev-parse --path-format=absolute --git-common-dir)"`, which is the same from inside any worktree. `<remote>` and `<base>` are the remote and base branch from the settings.

Run `git fetch <remote> --prune`. For every worktree under `<root>/.claude/worktrees/` (`git worktree list`), when its branch is merged into `<remote>/<base>` (`git branch --merged <remote>/<base>`, or `gh pr list --state merged --head <branch>` returns a PR) and `git -C <worktree> status --porcelain` is empty: `git worktree remove <path>` and `git branch -D <branch>`. Use `-D`, since `-d` checks against the current HEAD, not `<remote>/<base>`, and refuses a merged branch whose remote branch the prune just removed; delete only branches one of the two checks showed merged. Never force-remove a worktree with uncommitted changes; list those to the developer and leave them.

## 2. Open a fresh worktree

1. Pick a branch name from the request as in the conventions the settings name. It can be renamed later with `git branch -m`.
2. `git worktree add --no-track -b <branch> <root>/.claude/worktrees/<slug> <remote>/<base>`
3. In the worktree: run the settings' install command.
4. Work in that worktree for the rest of the flow. The developer's own checkout and any unfinished branch stay untouched.

## 3. Grill the change

If the developer passed an issue, read it first (as the repo's `docs/agents/issue-tracker.md` describes) and state its title.

Read `<upstream>/grill-with-docs/SKILL.md` and follow it. Deviations:

- **`domain-modeling`, "Update GLOSSARY.md inline" and "Offer ADRs sparingly":** write the glossary and ADRs in the new worktree, never in the developer's checkout, so they travel with the change in its PR.
- **`grilling`, last paragraph ("The session is done when the frontier is empty"):** the last round always holds the classification question below, with your proposal as the recommended answer. An issue that already settles most decisions makes the grilling short; it still ends with the classification.

### Classification

Propose **small** or **large**; the developer confirms.

**Small** is one vertical slice: one PR, fits in one context window, and has no blocking edges (nothing has to land before another part can start). Everything else is **large**.

A new glossary term or ADR does not make a change large on its own.

## 4. Route

- Small: follow [SMALL.md](SMALL.md).
- Large: follow [LARGE.md](LARGE.md).

Both end with the code review in [REVIEW.md](REVIEW.md) and the PR in [PR.md](PR.md).

## Commands

The typecheck, one-test-file and full-check commands are in the settings. Run the full checks once at the end, not after every slice. Commits follow the conventions the settings name.
