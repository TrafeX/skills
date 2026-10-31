#!/usr/bin/env bash
# Run the app of the current git worktree and serve it on the tailnet over
# HTTPS, so it can be opened from a phone. What to run comes from the first
# ```json block in the worktree's docs/agents/preview.md (format: SKILL.md).
#
#   preview.sh start [settings.md]   start the preview of this worktree
#   preview.sh stop [--purge]        stop it; --purge also removes compose volumes
#   preview.sh exec <compose args>   docker compose on this worktree's preview stack
#   preview.sh list                  running previews of every worktree of this repo
#
# State lives in the worktree's own git dir, so it is never committed.
# PREVIEW_NO_SERVE=1 skips Tailscale (local test only).
set -euo pipefail

die() { echo "preview: $*" >&2; exit 1; }

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repo"
gitdir=$(git rev-parse --absolute-git-dir)
main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
state_dir="$gitdir/preview"
state="$state_dir/state"
compose_file="$state_dir/compose.json"

repo=$(basename "$main")
slug=$(basename "$root")
name=$repo
[[ $root != "$main" ]] && name="$repo-$slug"
project=$(printf '%s' "$name" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_-' '-' | sed 's/^[^a-z0-9]*//')

no_serve() { [[ ${PREVIEW_NO_SERVE:-} == 1 ]]; }

# ---------------------------------------------------------------- settings

read_spec() {
  local file=$1
  [[ -f $file ]] || die "no settings: $file is missing"
  awk '/^```json[[:space:]]*$/ {on=1; next} on && /^```/ {exit} on {print}' "$file" >"$state_dir/spec.json"
  [[ -s $state_dir/spec.json ]] || die "no \`\`\`json block in $file"
  jq -e . "$state_dir/spec.json" >/dev/null || die "the json block in $file is not valid JSON"
  kind=$(jq -r '.kind // empty' "$state_dir/spec.json")
  [[ $kind == compose || $kind == command ]] || die "settings: kind must be \"compose\" or \"command\""
}

spec() { jq -r "$@" "$state_dir/spec.json"; }

# Replace the preview variables in a string. Single-quoted in the settings,
# they reach here unexpanded.
expand() {
  local s=$1 v
  for v in PREVIEW_PORT PREVIEW_URL PREVIEW_ORIGIN PREVIEW_HOST PREVIEW_PROJECT MAIN_PROJECT; do
    s=${s//\$\{$v\}/${!v}}
    s=${s//\$$v/${!v}}
  done
  printf '%s' "$s"
}

# ---------------------------------------------------------------- ports

port_busy() { ss -ltnH "sport = :$1" | grep -q .; }

serve_ports() {
  no_serve && return 0
  tailscale serve status --json 2>/dev/null | jq -r '.TCP // {} | keys[]' 2>/dev/null || true
}

# A port from the pool, stable per worktree while it is free. Route i listens
# on port + 1000*i on 127.0.0.1; route 0 shares the number of the tailnet port.
pick_port() {
  local range lo hi size start i p r ok taken
  range=$(spec '.ports // "4000-4999"')
  lo=${range%-*}; hi=${range#*-}
  size=$((hi - lo + 1))
  start=$(( $(printf '%s' "$root" | cksum | cut -d' ' -f1) % size ))
  taken=$(serve_ports)
  for ((i = 0; i < size; i++)); do
    p=$((lo + (start + i) % size))
    grep -qx "$p" <<<"$taken" && continue
    ok=1
    for ((r = 0; r < routes; r++)); do
      port_busy $((p + 1000 * r)) && { ok=0; break; }
    done
    [[ $ok == 1 ]] && { echo "$p"; return; }
  done
  echo "preview: no free port in $range; running previews:" >&2
  cmd_list >&2
  exit 1
}

# ---------------------------------------------------------------- tailscale

ts_host() { tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//'; }

check_tailscale() {
  command -v tailscale >/dev/null || die "tailscale is not installed"
  local certs
  certs=$(tailscale status --json | jq -r '.CertDomains // [] | length')
  [[ $certs -gt 0 ]] || die "HTTPS certificates are off in this tailnet. Turn on 'HTTPS Certificates' at https://login.tailscale.com/admin/dns, then retry."
}

serve_route() {
  local path=$1 target=$2 out args=(--bg "--https=$PREVIEW_PORT")
  [[ $path != / ]] && args+=("--set-path=$path")
  if ! out=$(tailscale serve "${args[@]}" "http://127.0.0.1:$target" 2>&1); then
    echo "$out" >&2
    grep -qi 'access denied\|operator\|permission' <<<"$out" \
      && die "tailscale serve needs operator rights. Run once: sudo tailscale set --operator=\$USER"
    die "tailscale serve failed"
  fi
}

# ---------------------------------------------------------------- compose

compose() { docker compose -p "$project" --project-directory "$root" -f "$compose_file" "$@"; }

main_project() {
  (cd "$main" && docker compose config --format json 2>/dev/null | jq -r '.name') || echo "$repo"
}

# The project's compose config, made into a stack of its own: no fixed
# container, network or volume names, no subnets, no Traefik labels, no host
# ports except the routes, on 127.0.0.1.
write_compose() {
  local routes_json env_json users_json uid
  routes_json=$(spec --argjson base "$PREVIEW_PORT" '[.routes | to_entries[] | {service: .value.service, target: .value.port, published: (($base + 1000 * .key) | tostring)}]')
  env_json=$(jq -c '.env // {}' "$state_dir/spec.json")
  env_json=$(expand "$env_json")
  users_json=$(jq -c '.host_user // []' "$state_dir/spec.json")
  uid="$(id -u):$(id -g)"
  (cd "$root" && docker compose -p "$project" config --format json) | jq \
    --argjson routes "$routes_json" --argjson env "$env_json" \
    --argjson users "$users_json" --arg uid "$uid" '
      .services |= map_values(
        del(.ports, .container_name)
        | if .labels then .labels |= with_entries(select(.key | startswith("traefik.") | not)) else . end)
      | if has("networks") then .networks |= map_values(if .external then . else del(.name, .ipam) end) else . end
      | if has("volumes") then .volumes |= map_values(if .external then . else del(.name) end) else . end
      | reduce $routes[] as $r (.;
          if .services[$r.service] == null then error("no service \($r.service) in the compose config") else . end
          | .services[$r.service].ports += [{target: $r.target, published: $r.published, host_ip: "127.0.0.1", protocol: "tcp"}])
      | reduce ($env | to_entries[]) as $e (.;
          .services[$e.key].environment = ((.services[$e.key].environment // {}) + $e.value))
      | reduce $users[] as $u (.;
          .services[$u].user = $uid
          | .services[$u].environment = ({HOME: "/tmp"} + (.services[$u].environment // {})))
    ' >"$compose_file"
}

# ---------------------------------------------------------------- steps

# Gitignored files the worktree needs, copied from the main checkout.
copy_files() {
  local f
  while IFS= read -r f; do
    [[ -z $f || -e $root/$f ]] && continue
    [[ -e $main/$f ]] || die "copy: $f is missing in the main checkout too"
    mkdir -p "$(dirname "$root/$f")"
    cp -a "$main/$f" "$root/$f"
    echo "copied $f from the main checkout"
  done < <(spec '.copy // [] | .[]')
}

# Run the steps of one phase ("before" or "setup"). A step with a service runs
# in that compose service (before: a throwaway container; setup: the running
# one); a step without runs on the host in the worktree.
run_steps() {
  local phase=$1 n i service run
  n=$(spec ".$phase // [] | length")
  for ((i = 0; i < n; i++)); do
    service=$(spec ".${phase}[$i].service // empty")
    run=$(expand "$(spec ".${phase}[$i].run")")
    echo "--- $phase: ${service:+[$service] }$run"
    if [[ -n $service ]]; then
      [[ $kind == compose ]] || die "$phase: a step with a service needs kind compose"
      if [[ $phase == before ]]; then
        compose run --rm --no-deps -T "$service" sh -c "$run"
      else
        compose exec -T "$service" sh -c "$run"
      fi
    else
      (cd "$root" && env "${step_env[@]}" bash -o pipefail -c "$run")
    fi
  done
}

start_command() {
  local cmd envs=() kv
  cmd=$(expand "$(spec '.command // empty')")
  [[ -n $cmd ]] || die "settings: kind command needs a command"
  while IFS= read -r kv; do
    [[ -n $kv ]] && envs+=("$(expand "$kv")")
  done < <(spec '.env // {} | to_entries[] | "\(.key)=\(.value)"')
  (
    cd "$root"
    env "${step_env[@]}" PORT="$PREVIEW_PORT" __VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS="$PREVIEW_HOST" "${envs[@]}" \
      setsid bash -c "$cmd" >"$state_dir/log" 2>&1 </dev/null &
    echo $! >"$state_dir/pid"
  )
  pid=$(cat "$state_dir/pid")
}

wait_http() {
  local r port i
  for ((r = 0; r < routes; r++)); do
    port=$((PREVIEW_PORT + 1000 * r))
    for ((i = 1; ; i++)); do
      curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$port/" && break
      if [[ $kind == command ]] && ! kill -0 "$pid" 2>/dev/null; then
        echo "--- last lines of $state_dir/log ---" >&2
        tail -n 30 "$state_dir/log" >&2
        die "the command exited before it answered on port $port"
      fi
      ((i < 300)) || die "nothing answered on http://127.0.0.1:$port within 300s"
      sleep 1
    done
  done
}

# ---------------------------------------------------------------- commands

write_state() {
  printf 'kind=%q\nPREVIEW_PORT=%q\nurl=%q\nproject=%q\npid=%q\n' \
    "$kind" "$PREVIEW_PORT" "$PREVIEW_URL" "$project" "${pid:-}" >"$state"
}

read_state() {
  [[ -f $state ]] || return 1
  # shellcheck disable=SC1090
  source "$state"
}

cmd_start() {
  local settings=${1:-$root/docs/agents/preview.md}
  if read_state; then die "a preview already runs for this worktree: $url (stop it first)"; fi
  mkdir -p "$state_dir"
  read_spec "$settings"
  no_serve || check_tailscale

  if [[ $kind == compose ]]; then
    routes=$(spec '.routes // [] | length')
    [[ $routes -gt 0 ]] || die "settings: kind compose needs routes"
    [[ $(spec '.routes[0].path') == / ]] || die "settings: the first route must be \"/\""
  else
    routes=1
  fi

  if no_serve; then PREVIEW_HOST=localhost; else PREVIEW_HOST=$(ts_host); fi
  PREVIEW_PORT=$(pick_port)
  PREVIEW_ORIGIN="https://$PREVIEW_HOST:$PREVIEW_PORT"
  PREVIEW_URL="$PREVIEW_ORIGIN/"
  PREVIEW_PROJECT=$project
  MAIN_PROJECT=$(main_project)
  url=$PREVIEW_URL
  step_env=(PREVIEW_PORT="$PREVIEW_PORT" PREVIEW_URL="$PREVIEW_URL" PREVIEW_ORIGIN="$PREVIEW_ORIGIN"
    PREVIEW_HOST="$PREVIEW_HOST" PREVIEW_PROJECT="$PREVIEW_PROJECT" MAIN_PROJECT="$MAIN_PROJECT"
    PREVIEW_COMPOSE="docker compose -p $project --project-directory $root -f $compose_file")

  write_state
  # From here on, any failure stops whatever did start.
  trap 'echo "preview: start failed, cleaning up" >&2; cmd_stop >/dev/null 2>&1 || true' EXIT

  copy_files
  if [[ $kind == compose ]]; then
    write_compose
    run_steps before
    compose up -d --build --remove-orphans
  else
    run_steps before
    start_command
    write_state
  fi
  run_steps setup
  wait_http

  if ! no_serve; then
    local r path
    for ((r = 0; r < routes; r++)); do
      if [[ $kind == compose ]]; then path=$(spec ".routes[$r].path"); else path=/; fi
      serve_route "$path" $((PREVIEW_PORT + 1000 * r))
    done
  fi
  trap - EXIT

  echo "preview: $PREVIEW_URL"
  echo "worktree: $root"
  [[ $kind == compose ]] && echo "compose project: $project"
  [[ $kind == command ]] && echo "log: $state_dir/log"
  return 0
}

cmd_stop() {
  read_state || die "no preview runs for this worktree"
  no_serve || tailscale serve --https="$PREVIEW_PORT" off >/dev/null 2>&1 || true
  case $kind in
    compose)
      if [[ ${1:-} == --purge ]]; then compose down --volumes --remove-orphans; else compose down --remove-orphans; fi ;;
    command)
      [[ -n $pid ]] && { kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true; } ;;
  esac
  rm -f "$state" "$state_dir/pid"
  echo "preview stopped: $url"
}

cmd_exec() {
  read_state || die "no preview runs for this worktree"
  [[ $kind == compose ]] || die "exec only works for a compose preview"
  compose "$@"
}

cmd_list() {
  local wt f
  git worktree list --porcelain | sed -n 's/^worktree //p' | while read -r wt; do
    f="$(git -C "$wt" rev-parse --absolute-git-dir)/preview/state"
    [[ -f $f ]] || continue
    (source "$f"; echo "$url  $kind  $wt")
  done
}

case ${1:-} in
  start) shift; cmd_start "$@" ;;
  stop) shift; cmd_stop "$@" ;;
  exec) shift; cmd_exec "$@" ;;
  list) cmd_list ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
