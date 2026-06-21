#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=lib/load-env.sh
source "${ROOT}/scripts/lib/load-env.sh"
load_env "$ROOT"

DEV_PORT="${DEV_PORT:-8080}"
export SCOUT_DEV_PUBLIC_URL="http://localhost:${DEV_PORT}"

"${ROOT}/scripts/sync-dashboard-bootstrap.sh"

BASE="http://127.0.0.1:${DEV_PORT}"
if ! curl -fsS "${BASE}/health" >/dev/null 2>&1; then
  echo ""
  echo "Scout server is not running at ${BASE}"
  echo "Start it in another terminal first:"
  echo "  ./dev server"
  echo "  # or: DEV_PORT=${DEV_PORT} ./dev server"
  exit 1
fi

echo "==> API ${BASE}/api/dashboard/config"
cd "${ROOT}/apps/dashboard"
flutter run -d chrome
