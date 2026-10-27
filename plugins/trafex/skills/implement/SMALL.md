# Small route

Read `<upstream>/implement/SKILL.md` and follow it in the worktree from [SKILL.md](SKILL.md), with these deviations. Upstream `implement` has no numbered steps, so each deviation quotes the start of the sentence it overrides.

- **`implement`, "Implement the work described by the user in the spec or tickets":** the spec is the issue when there is one. Without an issue, write the grilling's outcome out as a spec of a few lines (the problem, the behaviour after the change, what is out of scope) and have the developer confirm it. The code review's Spec axis checks against this text.
- **`implement`, "Call the Skill tool with "tdd" where possible, at pre-agreed seams":** read `<upstream>/tdd/SKILL.md` and follow it, with these deviations:
  - Propose the seams in one line, each with what it catches and misses (for example "Seams: `decide()` (catches the state change, misses the shell's retries). OK?"), and let the developer confirm in one word. Prefer the seams the settings point to. This replaces `tdd`'s "Seams: where tests go" confirmation; the rest of `tdd` applies unchanged.
  - Changes that touch no code behaviour (only docs, ADRs, glossary, prompt text or skill text) skip `tdd` and the seams. Say so to the developer. They still get the code review.
  - Per slice, commit the failing test once you have seen it fail, then commit the code that makes it pass, so the history shows red before green. Keep the failing run's output for the PR's Evidence.
- **`implement`, "Run typechecking regularly":** the commands are in the settings.
- **`implement`, "Once done, call the Skill tool with "code-review"":** run the code review in [REVIEW.md](REVIEW.md) instead.
- **`implement`, "Commit your work to the current branch":** commit the grilling's docs and the work to the worktree's branch, then open the PR as in [PR.md](PR.md).
