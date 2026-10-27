# Project settings

The repo's `docs/agents/implement.md` holds what this way of working needs to know about the repo. Keep it short; the skill reads it at the start of every change.

## Format

```markdown
# implement

Settings for the `trafex:implement` skill.

- Remote: `upstream`
- Base branch: `main`
- Install: `npm ci`
- Typecheck: `npm run typecheck`
- One test file: `npx vitest run <path>`, from the package directory
- Full checks: `npm run lint && npm run typecheck && npm test`
- Conventions: `CODING_STANDARDS.md` (code, tests, docs, commits, branches)
- Glossary: `GLOSSARY.md`
- ADRs: `docs/adr/`
- Seams: ADR 0003
- External APIs: GitHub, Linear

## Vocabulary

- Our own code review of a change is "the code review", never "Review": the glossary reserves that word.
```

Every line is optional except the remote, the base branch and the full checks. Leave out what the repo does not have: without a seams line the seams come from `tdd` alone, without external APIs the Correctness brief names none.

## When the file is missing

Before step 1, propose the values from the repo itself: `git remote -v` and the default branch for the remote and base branch, the package manifest or Makefile for the commands, and the files that exist for the conventions, glossary and ADRs. Show the proposal to the developer and let them correct it. Use the confirmed values for this change, and after step 2 write them to `docs/agents/implement.md` in the new worktree, so the file travels with the change in its PR.
