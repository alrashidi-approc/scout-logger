#!/usr/bin/env bash
# Local dev without uploading to Hetzner.
#
#   ./scripts/dev-local.sh          # db + server (foreground)
#   ./scripts/dev-local.sh docker   # full stack like production (Podman/Docker)
#   ./scripts/dev-local.sh test     # send sample event (server must be running)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=lib/load-env.sh
source "${ROOT}/scripts/lib/load-env.sh"
# shellcheck source=lib/container-runtime.sh
source "${ROOT}/scripts/lib/container-runtime.sh"
load_env "$ROOT"

PORT="${PORT:-8080}"
DB_PORT="${DB_PORT:-5433}"
DASHBOARD_WEB_PATH="${DASHBOARD_WEB_PATH:-scout/dashboard}"
DASHBOARD_WEB_PATH="${DASHBOARD_WEB_PATH#/}"
DASHBOARD_WEB_PATH="${DASHBOARD_WEB_PATH%/}"

cmd="${1:-server}"

start_db() {
  require_container_runtime
  echo "==> Starting Postgres on 127.0.0.1:${DB_PORT}..."
  compose_cmd -f docker-compose.yaml -f docker-compose.dev.yaml up -d db
}

case "$cmd" in
  db)
    start_db
    echo "DB_HOST=localhost DB_PORT=${DB_PORT} POSTGRES_USER=${POSTGRES_USER:-scout} POSTGRES_DB=${POSTGRES_DB:-scout}"
    ;;
  server)
    start_db
    export DB_HOST=localhost
    export DB_PORT
    echo "==> Server http://localhost:${PORT}  dashboard http://localhost:${PORT}/${DASHBOARD_WEB_PATH}/"
    echo "    (Rebuild UI once: cd apps/dashboard && flutter build web)"
    cd "${ROOT}/apps/server"
    dart run bin/server.dart
    ;;
  docker)
    case "${2:-up}" in
      up)
        if [[ ! -f "${ROOT}/apps/dashboard/build/web/index.html" ]]; then
          echo "Build dashboard first: ./dev dashboard"
          exit 1
        fi
        echo "==> Full stack (server + db) on http://localhost:${PORT}/"
        compose_cmd up --build -d
        for _ in $(seq 1 30); do
          if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
            echo "OK  http://127.0.0.1:${PORT}/health"
            echo "    http://127.0.0.1:${PORT}/${DASHBOARD_WEB_PATH}/"
            exit 0
          fi
          sleep 1
        done
        compose_cmd logs --tail=40 server
        exit 1
        ;;
      down)
        compose_cmd down "${@:3}"
        ;;
      reset)
        echo "==> Wiping Postgres volume and restarting..."
        compose_cmd down -v
        compose_cmd up --build -d
        ;;
      logs)
        compose_cmd logs -f server
        ;;
      *)
        compose_cmd "${@:2}"
        ;;
    esac
    ;;
  dashboard)
    exec "${ROOT}/scripts/dev-dashboard.sh"
    ;;
  seed)
    exec bash "${ROOT}/scripts/seed-demo-data.sh"
    ;;
  test)
    BASE="http://127.0.0.1:${PORT}"
    echo "==> Health..."
    curl -fsS "${BASE}/health" | head -c 200
    echo ""
    KEY="${INGEST_KEY:-}"
    if [[ -z "$KEY" ]]; then
      if [[ -n "${DASHBOARD_API_KEY:-}" ]]; then
        echo "==> Creating test project via admin API..."
        RESP="$(curl -fsS -X POST "${BASE}/api/projects" \
          -H "X-API-Key: ${DASHBOARD_API_KEY}" \
          -H "Content-Type: application/json" \
          -d '{"name":"dev-test"}' 2>&1)" || {
          echo "$RESP"
          echo ""
          echo "Admin API failed. Create a project in the dashboard, copy the sk_live_... key, then:"
          echo "  INGEST_KEY=sk_live_... ./dev test"
          exit 1
        }
        KEY="$(echo "$RESP" | sed -n 's/.*"ingestKey":"\([^"]*\)".*/\1/p')"
      fi
    fi
    if [[ -z "$KEY" ]]; then
      echo "Paste the project ingest key (starts with sk_live_, NOT the dashboard admin key):"
      read -r -p "INGEST_KEY: " KEY
    fi
    if [[ -z "$KEY" || "$KEY" != sk_live_* ]]; then
      echo ""
      echo "Need an ingest key (sk_live_...), not DASHBOARD_API_KEY (scout12345)."
      echo "Open ${BASE}/${DASHBOARD_WEB_PATH}/ → Projects → create project → copy DSN/key."
      exit 1
    fi
    echo "==> POST /v1/events/batch..."
    HTTP="$(curl -sS -o /tmp/scout-test-body.txt -w '%{http_code}' -X POST "${BASE}/v1/events/batch" \
      -H "Authorization: Bearer ${KEY}" \
      -H "Content-Type: application/json" \
      -d '{
        "events": [{
          "type": "error",
          "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
          "payload": {
            "message": "Local test error",
            "stack": "at main()",
            "release": "com.test@1.0.0+1",
            "environment": "local",
            "user": { "id": "local-user", "sessionId": "local-session" },
            "device": { "platform": "macos", "version": "1.0.0" }
          }
        }]
      }')"
    cat /tmp/scout-test-body.txt
    echo ""
    if [[ "$HTTP" != "200" && "$HTTP" != "202" ]]; then
      echo "Failed (HTTP ${HTTP}). Use sk_live_... from Projects, not DASHBOARD_API_KEY."
      exit 1
    fi
    echo "OK — refresh dashboard Issues / Events"
    ;;
  *)
    echo "Usage: $0 {server|db|docker|dashboard|seed|test}"
    echo "  docker up     — build + start containers (default)"
    echo "  docker down   — stop containers"
    echo "  docker reset  — wipe DB volume + restart (fixes password mismatch)"
    echo "  docker logs   — follow server logs"
    echo "  seed          — fill DB with demo errors/crashes for UI preview"
    exit 1
    ;;
esac
