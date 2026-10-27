# Pull request

Every PR body is written by following `<upstream>/pr/SKILL.md` (Summary, Evidence, Merge Danger), using the glossary's terms, followed by a line naming the issues it closes:

```markdown
<body from the pr skill>

Closes #<issue>
```

Leave out the `Closes` line when there is no issue. The PR title follows the commit subject rule in the conventions the settings name.

**Show the title and body to the developer before anything leaves the machine.** Only after they approve:

- Small route: `git push -u <remote> <branch>`, then `gh pr create --base <base> --title "<title>" --body-file <file>`.
- Large route: update the draft PR and mark it ready, as in [LARGE.md](LARGE.md) step 8.

Report the PR's URL.
