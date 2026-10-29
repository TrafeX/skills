# AGENTS.md

## Plugin version

Every commit that changes a file under `plugins/<plugin>/` also bumps `version` in that plugin's `.claude-plugin/plugin.json`, in the same commit. An installed plugin is a cached copy that only updates when the version changes (see `README.md`). Bump the minor version when the way of working changes, the patch version for a wording fix that changes no behaviour.
