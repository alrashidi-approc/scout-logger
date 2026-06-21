#!/usr/bin/env bash
# One-command deploy: build dashboard locally → rsync → Podman/Docker on Hetzner.
#
#   ./deploy
#
# Requires in .env:
#   HETZNER_HOST=root@YOUR_IP
#   HETZNER_DIR=/opt/scout-logger
#   PUBLIC_URL=https://your-domain-or-http://IP:8080
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=lib/load-env.sh
source "${ROOT}/scripts/lib/load-env.sh"
# shellcheck source=lib/ssh-opts.sh
source "${ROOT}/scripts/lib/ssh-opts.sh"

load_env "$ROOT"
init_ssh_opts

HETZNER_HOST="${HETZNER_HOST:-}"
HETZNER_DIR="${HETZNER_DIR:-/opt/scout-logger}"
PORT="${PORT:-8080}"
DASHBOARD_WEB_PATH="${DASHBOARD_WEB_PATH:-scout/dashboard}"
DASHBOARD_WEB_PATH="${DASHBOARD_WEB_PATH#/}"
DASHBOARD_WEB_PATH="${DASHBOARD_WEB_PATH%/}"
RSYNC_SSH="$(rsync_ssh_shell)"

if [[ -z "$HETZNER_HOST" ]]; then
  echo "Set HETZNER_HOST in .env (e.g. HETZNER_HOST=root@46.62.217.25)"
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync required (macOS: xcode-select --install)"
  exit 1
fi

check_ssh "$HETZNER_HOST"
check_server_port "$HETZNER_HOST" "$PORT" "$HETZNER_DIR"

if [[ "${SKIP_DASHBOARD_BUILD:-0}" != "1" ]]; then
  if ! command -v flutter >/dev/null 2>&1; then
    echo "Flutter not found. Install Flutter or set SKIP_DASHBOARD_BUILD=1"
    exit 1
  fi
  echo "==> Building dashboard (flutter web)..."
  "${ROOT}/scripts/sync-dashboard-bootstrap.sh"
  (cd "${ROOT}/apps/dashboard" && flutter build web)
  DASHBOARD_WEB_PATH="${DASHBOARD_WEB_PATH:-scout/dashboard}"
  DASHBOARD_WEB_PATH="${DASHBOARD_WEB_PATH#/}"
  DASHBOARD_WEB_PATH="${DASHBOARD_WEB_PATH%/}"
  INDEX="${ROOT}/apps/dashboard/build/web/index.html"
  if [[ -f "$INDEX" ]]; then
    sed -i '' "s|<base href=\"[^\"]*\">|<base href=\"/${DASHBOARD_WEB_PATH}/\">|" "$INDEX"
  fi
else
  echo "==> Skipping dashboard build (SKIP_DASHBOARD_BUILD=1)"
fi

if [[ ! -f "${ROOT}/apps/dashboard/build/web/index.html" ]]; then
  echo "Missing apps/dashboard/build/web — run without SKIP_DASHBOARD_BUILD=1"
  exit 1
fi

if [[ "${SKIP_SERVER_BUILD:-0}" != "1" ]]; then
  if ! command -v dart >/dev/null 2>&1; then
    echo "Dart not found. Install Flutter/Dart or set SKIP_SERVER_BUILD=1 (builds on VPS — slow)"
    exit 1
  fi
  echo "==> Building server binary for Linux (local cross-compile)..."
  "${ROOT}/scripts/build-server.sh"
else
  echo "==> Skipping local server build (SKIP_SERVER_BUILD=1 — VPS will compile; may hang on pub get)"
  if [[ ! -f "${ROOT}/apps/server/server" ]]; then
    echo "Missing apps/server/server — run without SKIP_SERVER_BUILD=1"
    exit 1
  fi
fi

RSYNC_EXCLUDES=(
  --exclude .git
  --exclude .ship
  --exclude .dart_tool
  --exclude apps/dashboard/.dart_tool
  --exclude apps/server/.dart_tool
  --exclude packages/scout_models/.dart_tool
  --exclude packages/scout_logger_plus
  --exclude node_modules
  --exclude agent-transcripts
)

echo "==> Uploading to ${HETZNER_HOST}:${HETZNER_DIR}..."
ssh "${SSH_OPTS[@]}" "$HETZNER_HOST" "mkdir -p '${HETZNER_DIR}'"
# shellcheck disable=SC2086
rsync -az --delete -e "${RSYNC_SSH}" "${RSYNC_EXCLUDES[@]}" "${ROOT}/" "${HETZNER_HOST}:${HETZNER_DIR}/"

echo "==> Uploading .env..."
# shellcheck disable=SC2086
rsync -az -e "${RSYNC_SSH}" "${ROOT}/.env" "${HETZNER_HOST}:${HETZNER_DIR}/.env"

if [[ "${RESET_DB:-0}" == "1" ]]; then
  echo "==> RESET_DB=1 — will wipe Postgres volume on server (all scout data lost)"
fi

echo "==> Bootstrap + build + start on server..."
ssh "${SSH_OPTS[@]}" "$HETZNER_HOST" bash -s <<EOF
set -euo pipefail
cd '${HETZNER_DIR}'
bash scripts/server-bootstrap.sh
if [[ "${RESET_DB:-0}" == "1" ]]; then
  bash scripts/compose.sh down -v 2>/dev/null || true
else
  bash scripts/compose.sh down 2>/dev/null || true
fi
bash scripts/compose.sh up -d --build
for i in \$(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    curl -fsS -o /dev/null -w "dashboard:%{http_code}\n" "http://127.0.0.1:${PORT}/${DASHBOARD_WEB_PATH}/"
    exit 0
  fi
  sleep 1
done
echo "Server did not become healthy within 60s"
bash scripts/compose.sh ps
bash scripts/compose.sh logs --tail=60 server
if bash scripts/compose.sh logs --tail=20 server 2>&1 | grep -q 'password authentication failed'; then
  echo ""
  echo "Postgres password mismatch — the data volume was initialized with a different POSTGRES_PASSWORD."
  echo "Fresh deploy (wipes scout data): RESET_DB=1 ./deploy"
fi
exit 1
EOF

IP="${HETZNER_HOST#*@}"
PUBLIC="${PUBLIC_URL:-http://${IP}:${PORT}}"

echo ""
echo "Deploy finished."
echo "  Health     ${PUBLIC}/health"
echo "  Dashboard  ${PUBLIC}/${DASHBOARD_WEB_PATH}/"
echo "  Logs       ssh ${HETZNER_HOST} 'cd ${HETZNER_DIR} && bash scripts/compose.sh logs -f server'"
echo "  Restart    ssh ${HETZNER_HOST} 'cd ${HETZNER_DIR} && bash scripts/compose.sh restart server'"

HEALTH="$(ssh "${SSH_OPTS[@]}" "$HETZNER_HOST" "curl -sf -o /dev/null -w '%{http_code}' http://127.0.0.1:${PORT}/health" || echo "000")"
if [[ "$HEALTH" != "200" ]]; then
  echo ""
  echo "Health check failed (${HEALTH}). Logs:"
  ssh "${SSH_OPTS[@]}" "$HETZNER_HOST" "cd '${HETZNER_DIR}' && bash scripts/compose.sh logs --tail=40 server" || true
  exit 1
fi
