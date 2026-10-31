#!/usr/bin/env bash
# Run the app of the current git worktree on its own port and serve it on the
# tailnet over HTTPS, so it can be opened from a phone.
#
#   preview.sh start compose <service> <container-port> [KEY=VALUE ...]
#   preview.sh start command '<shell command>' [KEY=VALUE ...]
#   preview.sh exec <docker compose args...>   (compose previews only)
#   preview.sh stop [--purge]
#   preview.sh list
#
# In the command and in KEY=VALUE, $PREVIEW_PORT and $PREVIEW_URL are replaced.
# State lives in the worktree's own git dir, so it is never committed.
# PREVIEW_NO_SERVE=1 skips Tailscale (local test only).
set -euo pipefail

die() { echo "preview: $*" >&2; exit 1; }

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repo"
gitdir=$(git rev-parse --absolute-git-dir)
state_dir="$gitdir/preview"
state="$state_dir/state"

repo=$(basename "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")
slug=$(basename "$root")
name=$repo
[[ $slug != "$repo" ]] && name="$repo-$slug"
project=$(printf '%s' "$name" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_-' '-' | sed 's/^[^a-z0-9]*//')

ts_host() {
  tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//'
}

port_busy() { ss -ltnH "sport = :$1" | grep -q .; }

pick_port() {
  local n p
  n=$(printf '%s' "$root" | cksum | cut -d' ' -f1)
  p=$((4000 + n % 1000))
  while port_busy "$p"; do p=$((p + 1)); done
  echo "$p"
}

expand() {
  local s=$1
  s=${s//\$PREVIEW_PORT/$port}
  s=${s//\$\{PREVIEW_PORT\}/$port}
  s=${s//\$PREVIEW_URL/$url}
  s=${s//\$\{PREVIEW_URL\}/$url}
  printf '%s' "$s"
}

read_state() {
  [[ -f $state ]] || return 1
  # shellcheck disable=SC1090
  source "$state"
}

check_tailscale() {
  command -v tailscale >/dev/null || die "tailscale is not installed"
  local certs
  certs=$(tailscale status --json | jq -r '.CertDomains // [] | length')
  [[ $certs -gt 0 ]] || die "HTTPS certificates are off in this tailnet. Turn on 'HTTPS Certificates' at https://login.tailscale.com/admin/dns, then retry."
}

serve_on() {
  if ! out=$(tailscale serve --bg --https="$port" "http://127.0.0.1:$port" 2>&1); then
    echo "$out" >&2
    if grep -qi 'access denied\|operator\|permission' <<<"$out"; then
      die "tailscale serve needs operator rights. Run once: sudo tailscale set --operator=\$USER"
    fi
    die "tailscale serve failed"
  fi
}

serve_off() { tailscale serve --https="$1" off >/dev/null 2>&1 || true; }

wait_http() {
  local i
  for i in $(seq 1 180); do
    if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$port/"; then return 0; fi
    if [[ $kind == command ]] && ! kill -0 "$pid" 2>/dev/null; then
      echo "--- last lines of $state_dir/log ---" >&2
      tail -n 30 "$state_dir/log" >&2
      die "the command exited before it answered on port $port"
    fi
    sleep 1
  done
  die "nothing answered on http://127.0.0.1:$port within 180s"
}

compose() {
  docker compose -p "$project" --project-directory "$root" -f "$state_dir/compose.json" "$@"
}

start_compose() {
  local service=$1 cport=$2; shift 2
  local envjson='{}' kv
  for kv in "$@"; do
    kv=$(expand "$kv")
    envjson=$(jq -c --arg k "${kv%%=*}" --arg v "${kv#*=}" '. + {($k): $v}' <<<"$envjson")
  done
  (cd "$root" && docker compose -p "$project" config --format json) \
    | jq --arg svc "$service" --argjson cport "$cport" --argjson port "$port" --argjson env "$envjson" '
        if .services[$svc] == null then error("no service \($svc) in the compose config") else . end
        | .services |= with_entries(
            .value |= (del(.ports) | del(.container_name))
          )
        | .services[$svc].ports = [{target: $cport, published: ($port|tostring), host_ip: "127.0.0.1", protocol: "tcp"}]
        | .services[$svc].environment = ((.services[$svc].environment // {}) + $env)
      ' >"$state_dir/compose.json"
  compose up -d --build --remove-orphans
}

start_command() {
  local cmd; cmd=$(expand "$1"); shift
  local envs=() kv
  for kv in "$@"; do envs+=("$(expand "$kv")"); done
  (
    cd "$root"
    env PORT="$port" PREVIEW_PORT="$port" PREVIEW_URL="$url" \
      __VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS="$host" "${envs[@]}" \
      setsid bash -c "$cmd" >"$state_dir/log" 2>&1 </dev/null &
    echo $! >"$state_dir/pid"
  )
  pid=$(cat "$state_dir/pid")
}

cmd_start() {
  local kind_arg=${1:-}; shift || true
  [[ $kind_arg == compose || $kind_arg == command ]] || die "usage: start compose <service> <port> [K=V...] | start command '<cmd>' [K=V...]"
  [[ ${PREVIEW_NO_SERVE:-} == 1 ]] || check_tailscale
  if read_state; then
    die "a preview already runs for this worktree: $url (stop it first)"
  fi
  mkdir -p "$state_dir"
  if [[ ${PREVIEW_NO_SERVE:-} == 1 ]]; then host=localhost; else host=$(ts_host); fi
  port=$(pick_port)
  url="https://$host:$port/"
  kind=$kind_arg
  case $kind in
    compose) [[ $# -ge 2 ]] || die "usage: start compose <service> <container-port> [K=V...]" ;;
    command) [[ $# -ge 1 ]] || die "usage: start command '<cmd>' [K=V...]" ;;
  esac
  write_state() {
    printf 'kind=%q\nport=%q\nurl=%q\nproject=%q\npid=%q\n' "$kind" "$port" "$url" "$project" "${pid:-}" >"$state"
  }
  write_state
  # From here on, any failure stops whatever did start.
  trap 'echo "preview: start failed, cleaning up" >&2; cmd_stop >/dev/null 2>&1 || true' EXIT
  case $kind in
    compose) start_compose "$@" ;;
    command) start_command "$@" ;;
  esac
  write_state
  wait_http
  [[ ${PREVIEW_NO_SERVE:-} == 1 ]] || serve_on
  trap - EXIT
  echo "preview: $url"
  echo "worktree: $root"
  [[ $kind == compose ]] && echo "compose project: $project"
  [[ $kind == command ]] && echo "log: $state_dir/log"
  return 0
}

cmd_stop() {
  read_state || die "no preview runs for this worktree"
  serve_off "$port"
  case $kind in
    compose)
      if [[ ${1:-} == --purge ]]; then compose down --volumes --remove-orphans; else compose down --remove-orphans; fi ;;
    command)
      kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true ;;
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
  local wt
  git worktree list --porcelain | sed -n 's/^worktree //p' | while read -r wt; do
    local f
    f="$(git -C "$wt" rev-parse --absolute-git-dir)/preview/state"
    [[ -f $f ]] || continue
    ( source "$f"; echo "$url  $kind  $wt" )
  done
}

case ${1:-} in
  start) shift; cmd_start "$@" ;;
  stop) shift; cmd_stop "$@" ;;
  exec) shift; cmd_exec "$@" ;;
  list) cmd_list ;;
  *) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
