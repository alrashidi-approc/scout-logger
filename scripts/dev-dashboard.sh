#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"${ROOT}/scripts/sync-dashboard-bootstrap.sh"
cd "${ROOT}/apps/dashboard"
flutter run -d chrome
