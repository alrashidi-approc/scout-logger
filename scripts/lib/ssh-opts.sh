#!/usr/bin/env bash
# Build SSH/rsync options from .env (call after load_env).

init_ssh_opts() {
  SSH_OPTS=(-o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new)

  if [[ -n "${HETZNER_SSH_PORT:-}" ]]; then
    SSH_OPTS+=(-p "$HETZNER_SSH_PORT")
  fi

  if [[ -n "${HETZNER_SSH_KEY:-}" ]]; then
    local key="${HETZNER_SSH_KEY/#\~/$HOME}"
    if [[ ! -f "$key" ]]; then
      echo "HETZNER_SSH_KEY not found: $key"
      exit 1
    fi
    SSH_OPTS+=(-i "$key")
  fi

  # CI / key-only hosts only — blocks password prompts
  if [[ "${SSH_BATCH_MODE:-0}" == "1" ]]; then
    SSH_OPTS+=(-o BatchMode=yes)
  fi
}

rsync_ssh_shell() {
  local parts=(ssh)
  local opt
  for opt in "${SSH_OPTS[@]}"; do
    parts+=("$opt")
  done
  printf '%q ' "${parts[@]}"
}

check_ssh() {
  local host="$1"
  echo "==> SSH check ${host}..."
  if ssh "${SSH_OPTS[@]}" "$host" "echo ok" >/dev/null 2>&1; then
    return 0
  fi

  echo ""
  echo "Cannot SSH to ${host} with non-interactive options."
  echo ""
  echo "Common fixes:"
  echo "  1. Add your Mac key to the server (recommended — one-time):"
  echo "       ssh-copy-id ${host}"
  echo "  2. Or set in .env if you use a non-default key:"
  echo "       HETZNER_SSH_KEY=~/.ssh/your_key"
  echo "  3. Or custom port:"
  echo "       HETZNER_SSH_PORT=22"
  echo ""
  echo "Manual test: ssh ${SSH_OPTS[*]} ${host}"
  echo "(Deploy does not use BatchMode so password auth can work, but rsync will ask many times — use a key.)"
  exit 1
}

check_server_port() {
  local host="$1"
  local port="$2"
  local deploy_dir="${3:-/opt/scout-logger}"
  local who
  who="$(ssh "${SSH_OPTS[@]}" "$host" "ss -ltnp 2>/dev/null | grep ':${port} ' || true" || true)"
  if [[ -z "$who" ]]; then
    return 0
  fi

  # Redeploy — our compose stack already owns this port (server may be crashed; compose down fixes it).
  if ssh "${SSH_OPTS[@]}" "$host" bash -s <<EOF
set -euo pipefail
if [[ ! -d '${deploy_dir}' ]]; then exit 1; fi
cd '${deploy_dir}'
if bash scripts/compose.sh ps 2>/dev/null | grep -qE '_server_|server.*${port}'; then exit 0; fi
if command -v podman >/dev/null 2>&1 && podman ps -a --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -qE 'scout-logger.*${port}'; then exit 0; fi
if command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -qE 'scout-logger.*${port}'; then exit 0; fi
exit 1
EOF
  then
    echo "==> Port ${port} — existing scout-logger; redeploy will restart it"
    return 0
  fi

  echo ""
  echo "Port ${port} is already in use on the server:"
  echo "  ${who}"
  echo ""
  echo "Fix one of:"
  echo "  A) Parallel staging — set in .env:"
  echo "       PORT=8081"
  echo "       PUBLIC_URL=http://YOUR_IP:8081"
  echo "  B) Cutover — stop old logplatform on :8080:"
  echo "       ssh ${host} 'cd /opt/logplatform && bash scripts/compose.sh down'"
  echo "     then keep PORT=8080 in .env"
  exit 1
}
