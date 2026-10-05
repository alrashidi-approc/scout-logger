#!/usr/bin/env bash
# Host-side Scout watchdog — catches dead Podman port publish (conmon wedge).
# Probes http://127.0.0.1:$PORT/health from the host; on repeated failure recreates
# the stack with compose down + up -d (never down -v).
#
# Status / test on the VPS:
#   systemctl status scout-watchdog.timer
#   journalctl -u scout-watchdog.service -n 50 --no-pager
#   # Simulate outage: cd /opt/scout-logger && bash scripts/compose.sh stop
#   # Wait ~2 minutes; then: curl -sS http://127.0.0.1:8081/health
#
# Installed by scripts/server-bootstrap.sh (systemd timer every 1 minute).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${SCOUT_WATCHDOG_STATE:-/var/lib/scout-logger}"
FAIL_FILE="${STATE_DIR}/watchdog-fails"
COOLDOWN_FILE="${STATE_DIR}/watchdog-last-recreate"
FAIL_THRESHOLD="${SCOUT_WATCHDOG_FAILS:-2}"
COOLDOWN_SECS="${SCOUT_WATCHDOG_COOLDOWN_SECS:-600}"

log() {
  echo "scout-watchdog: $*"
  logger -t scout-watchdog "$*" 2>/dev/null || true
}

mkdir -p "$STATE_DIR"

if [[ ! -f "${ROOT}/.env" ]]; then
  log "missing ${ROOT}/.env — skip"
  exit 0
fi

# shellcheck disable=SC1091
set -a && source "${ROOT}/.env" && set +a
PORT="${PORT:-8080}"

if curl -fsS --connect-timeout 3 --max-time 5 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
  rm -f "$FAIL_FILE"
  exit 0
fi

fails=0
if [[ -f "$FAIL_FILE" ]]; then
  fails="$(cat "$FAIL_FILE" 2>/dev/null || echo 0)"
fi
fails=$((fails + 1))
echo "$fails" >"$FAIL_FILE"
log "health failed on :${PORT} (fail ${fails}/${FAIL_THRESHOLD})"

if [[ "$fails" -lt "$FAIL_THRESHOLD" ]]; then
  exit 0
fi

now="$(date +%s)"
if [[ -f "$COOLDOWN_FILE" ]]; then
  last="$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)"
  if [[ "$last" =~ ^[0-9]+$ ]] && (( now - last < COOLDOWN_SECS )); then
    log "recreate skipped (cooldown ${COOLDOWN_SECS}s, last $((now - last))s ago)"
    exit 0
  fi
fi

log "recreating stack (compose down + up -d) — host :${PORT} unreachable"
cd "$ROOT"
bash scripts/compose.sh down
bash scripts/compose.sh up -d
echo "$now" >"$COOLDOWN_FILE"
rm -f "$FAIL_FILE"

# Brief wait then report
for _ in $(seq 1 30); do
  if curl -fsS --connect-timeout 2 --max-time 3 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    log "recovered — http://127.0.0.1:${PORT}/health ok"
    exit 0
  fi
  sleep 1
done
log "recreate finished but health still failing on :${PORT}"
exit 1
