# skills

TrafeX's general skills for Claude Code, as a plugin marketplace.

| Plugin       | Skill                          | What it does                                                                                                                         |
| ------------ | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `trafex`     | `trafex:implement`             | One way of working for every change to a repo: worktree, grilling, test-first build, three-axis code review and a PR.                |
| `dependabot` | `dependabot:dependabot-triage` | Weekly triage of open Dependabot PRs across all your GitHub repos: risk tiers, then mass-merge or mass-ignore groups behind green CI. |

Each plugin installs on its own; a plugin brings all of its skills.

## Install

From a local clone:

```
/plugin marketplace add ~/Projects/skills
/plugin install trafex@trafex
/plugin install dependabot@trafex
```

From GitHub, or for everyone who opens a project, in that project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "trafex": { "source": { "source": "github", "repo": "TrafeX/skills" } }
  },
  "enabledPlugins": { "trafex@trafex": true, "dependabot@trafex": true }
}
```

An installed plugin is a copy in `~/.claude/plugins/cache/`. After a change here, bump `version` in `plugins/<plugin>/.claude-plugin/plugin.json`, then run `/plugin marketplace update trafex` and `/plugin update <plugin>@trafex`.

While working on a skill, load it straight from disk instead: `claude --plugin-dir ~/Projects/skills/plugins/<plugin>`. A change shows up in the next session.

## Using `trafex:implement` in a repo

The skill reads the repo's `docs/agents/implement.md` for everything that differs per repo: remote, base branch, commands, conventions, glossary, seams and external APIs. The format is in `plugins/trafex/skills/implement/SETTINGS.md`. When the file is missing, the skill proposes the values and adds the file with the first change.

It also expects `docs/agents/issue-tracker.md`, as Matt Pocock's skills do (`/setup-matt-pocock-skills` writes it).

## Vendored upstream skills

`plugins/trafex/upstream/mattpocock/` is copied unchanged from [mattpocock/skills](https://github.com/mattpocock/skills) **1.3.1** (MIT, see its `LICENSE`):

| Skill             | Upstream path                        |
| ----------------- | ------------------------------------ |
| `code-review`     | `skills/engineering/code-review`     |
| `codebase-design` | `skills/engineering/codebase-design` |
| `domain-modeling` | `skills/engineering/domain-modeling` |
| `grill-with-docs` | `skills/engineering/grill-with-docs` |
| `grilling`        | `skills/productivity/grilling`       |
| `implement`       | `skills/engineering/implement`       |
| `implement-spec`  | `skills/engineering/implement-spec`  |
| `pr`              | `skills/engineering/pr`              |
| `tdd`             | `skills/engineering/tdd`             |
| `to-spec`         | `skills/engineering/to-spec`         |
| `to-tickets`      | `skills/engineering/to-tickets`      |

They sit outside `skills/`, so the plugin does not register them as skills of its own: `trafex:implement` reads them from their files. That pins the version, whatever `mattpocock-skills` plugin is installed next to it.

Never edit these copies. Every deviation from them lives in `plugins/trafex/skills/implement/`, written as "upstream skill X, step N: do Y instead", so the copies can be replaced wholesale.

### Updating to a new upstream version

1. Copy each directory above from the new upstream version over the copy here, whole directory, nothing else changed. With the `mattpocock-skills` plugin installed: `cp -r ~/.claude/plugins/cache/mattpocock/mattpocock-skills/<version>/skills/<upstream path> plugins/trafex/upstream/mattpocock/`.
2. Update the version at the top of this section.
3. Check every deviation in `plugins/trafex/skills/implement/` against the new text: does the step it names still exist, under the same number or quoted words, and does the deviation still make sense? Fix the deviations, not the copies.
4. Bump the plugin's `version` and commit; the diff of the copies is the upstream changelog to review.
