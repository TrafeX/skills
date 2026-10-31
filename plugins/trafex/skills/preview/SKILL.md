---
name: preview
description: "Runs the app of the current git worktree on its own port and serves it on the tailnet over HTTPS, so the developer can test work in progress from their phone. Handles Docker Compose stacks (isolated per worktree: own project name, own volumes, no clashing host ports) and plain commands like `npm run dev`. Use when the developer asks for a preview, a link to test on their phone, to start, stop or list previews, or to see the intermediate result of a worktree."
---

# preview

`<script>` is `preview.sh` in this skill's base directory. It does all the mechanics; this skill decides what to run. Run every command from inside the worktree to preview (the one you are working in, unless the developer names another).

## Start a preview

1. **Read the settings.** The worktree's `docs/agents/preview.md` says how to run the app (format below). When it is missing, propose the values from the repo: the compose file's web-facing service and its container port, or the `dev` script in `package.json`. Let the developer confirm, then write the file in the worktree, so it travels with the change.
2. **Start it.**
   - Compose: `<script> start compose <service> <container-port> [KEY=VALUE ...]`
   - Command: `<script> start command '<command>' [KEY=VALUE ...]`

   The KEY=VALUE pairs are the settings' `Env` lines. `$PREVIEW_PORT` and `$PREVIEW_URL` in them, and in the command, are replaced; quote them in single quotes so the shell leaves them alone. A command also gets `PORT`, and Vite gets the tailnet host as an allowed host.
3. **Run the setup**, once per new preview, when the settings have one. For compose, in a service: `<script> exec exec -T <service> <command>`. For a command preview, run it in the worktree.
4. **Give the link.** End your message with the URL from the `preview:` line, on its own line, so it can be tapped on the phone.

A compose preview is its own stack: project `<repo>-<worktree>`, fresh named volumes (so a fresh database, hence the setup step), and only the previewed service publishes a port, on `127.0.0.1`. `container_name` is dropped. The script builds images with `--build`.

## Stop, list, logs

- `<script> stop` stops the preview of the current worktree and frees its tailnet port. `stop --purge` also removes the compose volumes; use it when the worktree is about to be removed.
- `<script> list` shows the running previews of every worktree of this repo.
- Logs: for compose `<script> exec logs --tail 50 <service>`, for a command the `log:` file the start printed.

Before removing a worktree that has a preview, stop it with `--purge` first.

## When the start fails

The script stops whatever did start and prints why. Common causes:

- **HTTPS certificates are off** in the tailnet: the developer turns on "HTTPS Certificates" at https://login.tailscale.com/admin/dns.
- **Operator rights**: `sudo` does not work in your shell, so ask the developer to run `! sudo tailscale set --operator=$USER` once.
- **The command answers on another interface or port**: the app must listen on `127.0.0.1:$PREVIEW_PORT`. Vite's default `localhost` can bind to `::1` only; add `--host 127.0.0.1`.
- **The app answers but redirects or links to `localhost`**: set its base URL from `$PREVIEW_URL` with an `Env` line (Laravel `APP_URL`, Symfony `DEFAULT_URI`, and so on).

- **The phone times out** while the link works on the laptop: Shields Up is on (`tailscale debug prefs | jq .ShieldsUp`), which also blocks `tailscale serve`; the developer runs `! tailscale set --shields-up=false`. Otherwise the tailnet policy does not let the phone reach the laptop on TCP 4000–4999.

On the phone, the tailnet needs the Tailscale app, logged in to the same account. The laptop must stay awake while previews are in use.

## Settings format

`docs/agents/preview.md`:

```markdown
# preview

Settings for the `trafex:preview` skill.

- Kind: compose
- Service: `web`, port `80`
- Env: `APP_URL=$PREVIEW_URL`
- Setup: `php artisan migrate --seed`, in service `app`
```

or, for a command:

```markdown
- Kind: command
- Command: `npm run dev -- --host 127.0.0.1 --port $PREVIEW_PORT --strictPort`
- Setup: `npm ci`
```

`Env` and `Setup` may appear more than once, and are optional.
