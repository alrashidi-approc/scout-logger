#!/usr/bin/env bash
# Dump Postgres from Hetzner and optionally import into local dev DB.
#
#   ./scripts/pull-db.sh              # save to dumps/scout-YYYYMMDD-HHMM.sql
#   ./scripts/pull-db.sh --import     # dump + load into local ./dev db
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=lib/load-env.sh
source "${ROOT}/scripts/lib/load-env.sh"
# shellcheck source=lib/ssh-opts.sh
source "${ROOT}/scripts/lib/ssh-opts.sh"
# shellcheck source=lib/container-runtime.sh
source "${ROOT}/scripts/lib/container-runtime.sh"

load_env "$ROOT"
init_ssh_opts

IMPORT=0
for arg in "$@"; do
  [[ "$arg" == "--import" || "$arg" == "-i" ]] && IMPORT=1
done

HETZNER_HOST="${HETZNER_HOST:-}"
DB_USER="${POSTGRES_USER:-scout}"
DB_NAME="${POSTGRES_DB:-scout}"
LOCAL_PORT="${DB_PORT:-5433}"

if [[ -z "$HETZNER_HOST" ]]; then
  echo "Set HETZNER_HOST in .env"
  exit 1
fi

mkdir -p "${ROOT}/dumps"
OUT="${ROOT}/dumps/scout-$(date +%Y%m%d-%H%M).sql"

echo "==> Dumping ${DB_NAME} from ${HETZNER_HOST}..."
ssh "${SSH_OPTS[@]}" "$HETZNER_HOST" \
  "podman exec scout-logger_db_1 pg_dump -U ${DB_USER} --no-owner --no-acl ${DB_NAME}" >"$OUT"

BYTES="$(wc -c <"$OUT" | tr -d ' ')"
echo "==> Saved ${OUT} (${BYTES} bytes)"

if [[ "$IMPORT" != "1" ]]; then
  echo ""
  echo "Import locally:"
  echo "  ./scripts/pull-db.sh --import"
  echo "Or:"
  echo "  ./dev db && psql postgres://${DB_USER}:YOUR_PASSWORD@127.0.0.1:${LOCAL_PORT}/${DB_NAME} < ${OUT}"
  exit 0
fi

require_container_runtime
echo "==> Starting local Postgres on 127.0.0.1:${LOCAL_PORT}..."
compose_cmd -f docker-compose.yaml -f docker-compose.dev.yaml up -d db

for _ in $(seq 1 30); do
  if compose_cmd -f docker-compose.yaml -f docker-compose.dev.yaml exec -T db \
    pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> Importing (replaces local ${DB_NAME} data)..."
compose_cmd -f docker-compose.yaml -f docker-compose.dev.yaml exec -T db \
  psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS ${DB_NAME}; CREATE DATABASE ${DB_NAME};"
compose_cmd -f docker-compose.yaml -f docker-compose.dev.yaml exec -T db \
  psql -U "$DB_USER" -d "$DB_NAME" <"$OUT"

echo ""
echo "Done. Local DB has server data."
echo "  ./dev server"
echo "  open http://localhost:8080/scout/dashboard/"
