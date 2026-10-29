# Small route

Read `<upstream>/implement/SKILL.md` and follow it in the worktree from [SKILL.md](SKILL.md), with these deviations. Upstream `implement` has no numbered steps, so each deviation quotes the start of the sentence it overrides.

The building itself happens in one **implementer subagent**, so it starts with an empty context instead of the whole grilling. Everything that needs the developer stays with you: the spec, the seams, the code review and the PR.

- **`implement`, "Implement the work described by the user in the spec or tickets":** the spec is the issue when there is one. Without an issue, write the grilling's outcome out as a spec of a few lines (the problem, the behaviour after the change, what is out of scope) and have the developer confirm it. The code review's Spec axis checks against this text.
- **`implement`, "Call the Skill tool with "tdd" where possible, at pre-agreed seams":**
  - Before the subagent starts, propose the seams in one line, each with what it catches and misses (for example "Seams: `decide()` (catches the state change, misses the shell's retries). OK?"), and let the developer confirm in one word. Prefer the seams the settings point to. This replaces `tdd`'s "Seams: where tests go" confirmation, since the subagent cannot ask the developer.
  - Changes that touch no code behaviour (only docs, ADRs, glossary, prompt text or skill text) skip `tdd` and the seams. Say so to the developer. They still go to the subagent and still get the code review.
  - Commit the grilling's glossary and ADR changes to the worktree's branch first, so the subagent builds on the new language.
  - Then hand the work to one implementer subagent and wait for it. Its brief, besides the worktree's absolute path and a pointer to the issue (or the confirmed spec's text):
    - the confirmed seams; do not ask the developer to confirm them;
    - read `<upstream>/tdd/SKILL.md` (as an absolute path) and follow it, unless the change touches no code behaviour;
    - per slice, commit the failing test once it has seen it fail, then commit the code that makes it pass, so the history shows red before green; report each failing run's output, for the PR's Evidence;
    - run the settings' typecheck and its own test files (the one-test-file command), not the full checks;
    - do not run `code-review` or any other review;
    - when it meets a domain term that is not in the glossary, or the spec conflicts with an ADR, stop and report it instead of deciding: that decision is the developer's. Put it to the developer, update the glossary or ADR in the worktree, then let the subagent continue;
    - commit as in the conventions the settings name.
- **`implement`, "Run typechecking regularly":** the subagent runs the typecheck and single test files; once it is done, run the settings' full checks yourself.
- **`implement`, "Once done, call the Skill tool with "code-review"":** run the code review in [REVIEW.md](REVIEW.md) instead.
- **`implement`, "Commit your work to the current branch":** the work is already committed on the worktree's branch; open the PR as in [PR.md](PR.md).
