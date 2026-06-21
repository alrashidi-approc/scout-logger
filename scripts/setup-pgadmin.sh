#!/usr/bin/env bash
# pgAdmin for scout-logger Postgres (run on Hetzner as root).
# Re-run after every deploy — DB container IP changes and pgAdmin caches the old one.
#
#   cd /opt/scout-logger && bash scripts/setup-pgadmin.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PGADMIN_PORT="${PGADMIN_PORT:-5050}"
PGADMIN_EMAIL="${PGADMIN_EMAIL:-admin@admin.com}"
PGADMIN_PASSWORD="${PGADMIN_PASSWORD:-scout12345}"

if ! podman ps --format '{{.Names}}' | grep -q '^scout-logger_db_1$'; then
  echo "Start scout-logger first: bash scripts/compose.sh up -d"
  exit 1
fi

# Podman DNS on the compose network resolves service name "db" — do NOT pin a static IP
# (--add-host breaks after db container is recreated).
podman rm -f pgadmin 2>/dev/null || true

podman run -d \
  --name pgadmin \
  --network scout-logger_default \
  -p "${PGADMIN_PORT}:80" \
  -e "PGADMIN_DEFAULT_EMAIL=${PGADMIN_EMAIL}" \
  -e "PGADMIN_DEFAULT_PASSWORD=${PGADMIN_PASSWORD}" \
  --restart unless-stopped \
  docker.io/dpage/pgadmin4

SUBNET="$(podman network inspect scout-logger_default --format '{{range .Subnets}}{{.Subnet}}{{end}}' 2>/dev/null || echo '10.89.1.0/24')"

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "${PGADMIN_PORT}/tcp" 2>/dev/null || true
  ufw route allow "${PGADMIN_PORT}/tcp" 2>/dev/null || true
  ufw route allow proto tcp from any to "${SUBNET}" port 80 2>/dev/null || true
  ufw reload 2>/dev/null || true
fi

echo ""
echo "pgAdmin: http://$(curl -sf ifconfig.me 2>/dev/null || echo YOUR_IP):${PGADMIN_PORT}/"
echo "  Login: ${PGADMIN_EMAIL} / ${PGADMIN_PASSWORD}"
echo ""
echo "Register server → Connection:"
echo "  Host: db   Port: 5432   Database: scout"
echo "  User: scout   Password: (from .env POSTGRES_PASSWORD)"
echo ""
echo "Tip: re-run this script after ./deploy if pgAdmin cannot connect."
