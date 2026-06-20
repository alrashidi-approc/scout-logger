#!/usr/bin/env bash
# Populate the local DB with realistic demo events for dashboard UI testing.
#
#   ./dev seed
#   BASE=http://46.62.217.25:8081 ./dev seed   # remote server
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "${ROOT}/scripts/lib/load-env.sh"
load_env "$ROOT"

PORT="${PORT:-8080}"
BASE="${BASE:-http://127.0.0.1:${PORT}}"
ADMIN_KEY="${DASHBOARD_API_KEY:-}"

if ! curl -fsS "${BASE}/health" >/dev/null 2>&1; then
  echo "Server not running at ${BASE} — start with: ./dev docker"
  exit 1
fi

if [[ -z "$ADMIN_KEY" ]]; then
  echo "Set DASHBOARD_API_KEY in .env"
  exit 1
fi

echo "==> Demo project..."
RESP="$(curl -fsS -X POST "${BASE}/api/projects" \
  -H "X-API-Key: ${ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"name":"Demo App"}' 2>/dev/null || true)"

if [[ -n "$RESP" ]] && echo "$RESP" | grep -q '"ingestKey"'; then
  KEY="$(echo "$RESP" | sed -n 's/.*"ingestKey":"\([^"]*\)".*/\1/p')"
  PROJECT="$(echo "$RESP" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
  echo "    Created Demo App (${PROJECT})"
else
  PROJECTS="$(curl -fsS "${BASE}/api/projects" -H "X-API-Key: ${ADMIN_KEY}")"
  KEY="$(curl -fsS -X POST "${BASE}/api/projects" -H "X-API-Key: ${ADMIN_KEY}" -H "Content-Type: application/json" -d '{"name":"Demo App 2"}' | sed -n 's/.*"ingestKey":"\([^"]*\)".*/\1/p' || true)"
  if [[ -z "$KEY" ]]; then
    echo "Could not get ingest key — create a project in the dashboard first, then:"
    echo "  INGEST_KEY=sk_live_... ./dev seed"
    exit 1
  fi
fi

if [[ -n "${INGEST_KEY:-}" ]]; then
  KEY="$INGEST_KEY"
fi

if [[ -z "$KEY" || "$KEY" != sk_live_* ]]; then
  echo "Need INGEST_KEY=sk_live_... (create project in dashboard)"
  exit 1
fi

iso_days_ago() {
  local days="$1"
  if date -v-"${days}"d -u +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -d "-${days} days" +%Y-%m-%dT%H:%M:%SZ
  fi
}

post_event() {
  local country="$1"
  local type="$2"
  local ts="$3"
  local message="$4"
  local stack="$5"
  local user="$6"
  local release="$7"
  curl -fsS -X POST "${BASE}/v1/events/batch" \
    -H "Authorization: Bearer ${KEY}" \
    -H "CF-IPCountry: ${country}" \
    -H "Content-Type: application/json" \
    -d "{
      \"events\": [{
        \"type\": \"${type}\",
        \"timestamp\": \"${ts}\",
        \"payload\": {
          \"message\": \"${message}\",
          \"stack\": \"${stack}\",
          \"release\": \"${release}\",
          \"environment\": \"production\",
          \"user\": { \"id\": \"${user}\", \"sessionId\": \"sess-${user}\" },
          \"device\": { \"platform\": \"ios\", \"version\": \"${release}\" }
        }
      }]
    }" >/dev/null
}

echo "==> Seeding events (14-day spread, multiple countries)..."
countries=(US KW EG SA AE GB US KW EG)
users=(user-101 user-102 user-103 user-104 user-105 user-106 user-107 user-108)
releases=("com.demo.app@2.1.0+42" "com.demo.app@2.0.8+39" "com.demo.app@2.1.1+43")

# Spread events across last 14 days for trend chart
for day in 13 12 11 10 9 8 7 6 5 4 3 2 1 0; do
  ts="$(iso_days_ago "$day")"
  c="${countries[$((day % ${#countries[@]}))]}"
  u="${users[$((day % ${#users[@]}))]}"
  rel="${releases[$((day % ${#releases[@]}))]}"

  # Grouped payment error (same fingerprint → one issue, many events)
  post_event "$c" error "$ts" "Payment failed: card declined" \
    "PaymentException at CheckoutScreen.submit\n  at PaymentGateway.charge (payment.dart:88)\n  at CheckoutScreen._pay (checkout.dart:142)" \
    "$u" "$rel"

  post_event "$c" error "$ts" "Null check operator used on a null value" \
    "TypeError at ProfileScreen.build\n  at ProfileScreen.build (profile.dart:56)\n  at StatelessElement.build (framework.dart:5781)" \
    "user-201" "$rel"

  if (( day % 3 == 0 )); then
    post_event "$c" crash "$ts" "Fatal: EXC_BAD_ACCESS in ImageCache" \
      "0  DemoApp  0x0000000104a2b1c0 ImageCache._evict + 120\n1  DemoApp  0x0000000104a2c4f8 HomeScreen.didUpdateWidget + 84" \
      "user-301" "$rel"
  fi

  if (( day % 4 == 0 )); then
    post_event "$c" network "$ts" "POST /api/v1/orders returned 503" \
      "HttpException: Service Unavailable\n  at ApiClient.post (api.dart:210)" \
      "user-401" "$rel"
  fi
done

# Extra burst today
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for i in 1 2 3 4 5; do
  post_event "KW" error "$now" "Payment failed: card declined" \
    "PaymentException at CheckoutScreen.submit (payment.dart:88)" \
    "user-${i}00" "com.demo.app@2.1.1+43"
done

echo ""
echo "Done — open dashboard:"
echo "  ${BASE}/${DASHBOARD_WEB_PATH:-scout/dashboard}/"
echo ""
echo "Look for project \"Demo App\" — Overview, Issues, Events, Geography should have data."
