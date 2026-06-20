#!/usr/bin/env bash
# Run on the Hetzner server from the project directory (e.g. /opt/scout-logger).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing ${ENV_FILE} in $(pwd)"
  exit 1
fi

if command -v podman-compose >/dev/null 2>&1; then
  exec podman-compose --env-file "$ENV_FILE" "$@"
fi

if command -v podman >/dev/null 2>&1; then
  if ! systemctl is-active --quiet podman.socket 2>/dev/null; then
    systemctl enable --now podman.socket 2>/dev/null || true
  fi
  export DOCKER_HOST="${DOCKER_HOST:-unix:///run/podman/podman.sock}"
  exec podman compose --env-file "$ENV_FILE" "$@"
fi

if command -v docker >/dev/null 2>&1; then
  exec docker compose --env-file "$ENV_FILE" "$@"
fi

echo "Install podman or docker on the server."
exit 1
