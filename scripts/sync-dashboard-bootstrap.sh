#!/usr/bin/env bash
# Writes apps/dashboard/web/bootstrap.json from root .env (for flutter run on a different port).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
OUT="${ROOT}/apps/dashboard/web/bootstrap.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — copy .env.example to .env"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

DEV_PORT="${DEV_PORT:-8080}"
# Local flutter run — never use Hetzner PUBLIC_URL from .env unless explicitly set.
PUBLIC_URL="${SCOUT_DEV_PUBLIC_URL:-http://localhost:${DEV_PORT}}"

mkdir -p "$(dirname "$OUT")"
printf '{"publicUrl":"%s"}\n' "$PUBLIC_URL" > "$OUT"
echo "Wrote $OUT (publicUrl=$PUBLIC_URL)"
