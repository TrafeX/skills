---
name: preview
description: "Runs the app of the current git worktree and serves it on the tailnet over HTTPS, so the developer can test work in progress from their phone: the whole app, with several services (frontend and API) under one URL, a copy of the dev database and a working OAuth login. Handles Docker Compose stacks (isolated per worktree) and plain commands like `npm run dev`. Use when the developer asks for a preview, a link to test on their phone, to start, stop or list previews, or to see the intermediate result of a worktree."
---

# preview

`<script>` is `preview.sh` in this skill's base directory. It does all the work from the worktree's settings; this skill sets them up and reports. Run every command from inside the worktree to preview: the one you are working in, unless the developer names another.

## Start a preview

1. **Settings.** The worktree needs `docs/agents/preview.md` (format below). When it is missing, propose one from the repo: the compose services that serve HTTP and their container ports, the gitignored files they need (`env_file`s), install commands, and how the dev database is filled; or the `dev` script in `package.json`. Let the developer confirm, then write it in the worktree, so it travels with the change.
2. **Start:** `<script> start`. The first start of a compose preview builds images and installs dependencies; give the Bash call a long timeout (10 minutes).
3. **Give the link.** End your message with the URL from the `preview:` line, on its own line, so it can be tapped on the phone.

## Stop, list, logs

- `<script> stop` stops the preview of the current worktree and frees its port. `stop --purge` also removes the compose volumes (the database copy); use it before a worktree is removed.
- `<script> list` shows the running previews of every worktree of this repo.
- `<script> exec <compose args>` runs `docker compose` on the preview's stack, e.g. `exec logs --tail 50 api`.
- A command preview logs to the `log:` file the start printed.

## What a start does

1. Picks a port from `ports`: stable per worktree while it is free. The tailnet URL is `https://<laptop>.<tailnet>.ts.net:<port>/`.
2. Copies the `copy` files from the main checkout when the worktree lacks them.
3. Compose: writes the project's compose config as a stack of its own, project `<repo>-<worktree>`: no fixed container, network or volume names, no subnets, no `traefik.*` labels, and no host ports except one per route, on `127.0.0.1`. Services in `host_user` run as the developer's user with `HOME=/tmp`, so they leave no root-owned files in the worktree. Profiled services stay off.
4. Runs the `before` steps, then starts the app (`docker compose up -d --build`, or the command in the background).
5. Runs the `setup` steps, waits until every route answers, then serves route 0 at `/` and route *i* at its path on the tailnet. Tailscale strips the path: `/api/trpc` reaches the API as `/trpc`.

Any failure stops whatever started and prints why.

## Settings format

`docs/agents/preview.md`: prose for the reader, and the first ` ```json ` block for the script.

```json
{
  "kind": "compose",
  "ports": "4000-4009",
  "copy": ["api/.env", "frontend/.env"],
  "routes": [
    {"path": "/", "service": "frontend", "port": 3000},
    {"path": "/api", "service": "api", "port": 3000}
  ],
  "host_user": ["api", "frontend"],
  "env": {
    "frontend": {"API_URL": "$PREVIEW_ORIGIN/api"},
    "api": {"BASE_URL": "$PREVIEW_ORIGIN/api", "ALLOWED_ORIGINS": "$PREVIEW_ORIGIN"}
  },
  "before": [{"service": "api", "run": "npm ci"}],
  "setup": [{"run": "…"}]
}
```

- `kind`: `compose` or `command`. A command preview has `"command": "npm run dev -- --host 127.0.0.1 --port $PREVIEW_PORT --strictPort"` instead of `routes`, and a flat `env`. It must listen on `127.0.0.1:$PREVIEW_PORT`; it also gets `PORT`, and Vite gets the tailnet host as an allowed host.
- `ports`: the pool, default `4000-4999`. Route *i* listens locally on port + 1000·*i*.
- `routes`: the first is `/`. Same origin for all routes, so no CORS.
- `before` and `setup`: steps with a `service` run in that service: a throwaway container for `before`, the running one for `setup`. Steps without a `service` run with bash on the host, in the worktree.
- Variables, in `env`, `command` and steps: `$PREVIEW_PORT`, `$PREVIEW_URL` (with trailing `/`), `$PREVIEW_ORIGIN` (without), `$PREVIEW_HOST`, `$PREVIEW_PROJECT`, `$MAIN_PROJECT` (the compose project of the main checkout). Host steps also get `$PREVIEW_COMPOSE`, a `docker compose` command for the preview's stack.

Copy the main checkout's database in a host step, after waiting for the preview's database:

```
until $PREVIEW_COMPOSE exec -T database pg_isready -q; do sleep 1; done; docker compose -p $MAIN_PROJECT exec -T database pg_dump -U <user> <db> | $PREVIEW_COMPOSE exec -T database psql -q -U <user> <db>
```

When that step fails because the main stack does not run, say so and offer to start it, or to start the preview with an empty database (migrations and seeds) instead.

## OAuth

An OAuth provider such as Google needs every redirect URI registered exactly, port included; wildcards do not exist. Give such a project a small `ports` pool, point the app's callback base at `$PREVIEW_ORIGIN/<route>`, and have the developer register the callback URL of each port in the pool once.

## When the start fails

- **HTTPS certificates are off** in the tailnet: the developer turns on "HTTPS Certificates" at https://login.tailscale.com/admin/dns.
- **Operator rights**: `sudo` does not work in your shell, so ask the developer to run `! sudo tailscale set --operator=$USER` once.
- **A command answers on another interface or port**: it must listen on `127.0.0.1:$PREVIEW_PORT`. Vite's default `localhost` can bind to `::1` only; add `--host 127.0.0.1`.
- **The app answers but redirects or links to its usual host**: set its base URL from `$PREVIEW_ORIGIN` in `env`.
- **The phone times out** while the link works on the laptop: Shields Up is on (`tailscale debug prefs | jq .ShieldsUp`), which also blocks `tailscale serve`; the developer runs `! tailscale set --shields-up=false`. Otherwise the tailnet policy does not let the phone reach the laptop on the pool's ports.

The phone needs the Tailscale app, logged in to the same tailnet. The laptop must stay awake while previews are in use.
