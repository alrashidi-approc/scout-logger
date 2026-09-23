#!/usr/bin/env bash
# Copy a CA bundle into infra/ so the server image can build without apt-get.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/infra/ssl/ca-certificates.crt"

candidates=(
  /etc/ssl/cert.pem
  /etc/ssl/certs/ca-certificates.crt
  /usr/local/etc/ca-certificates/cert.pem
  /opt/homebrew/etc/ca-certificates/cert.pem
)

src=""
for f in "${candidates[@]}"; do
  if [[ -f "$f" && -s "$f" ]]; then
    src="$f"
    break
  fi
done

if [[ -z "$src" ]]; then
  echo "No CA certificate bundle found on this machine."
  echo "Install ca-certificates or place a PEM bundle at infra/ssl/ca-certificates.crt"
  exit 1
fi

mkdir -p "${ROOT}/infra/ssl"
cp "$src" "$OUT"
echo "==> CA certs: $src → infra/ssl/ca-certificates.crt ($(wc -c <"$OUT" | tr -d ' ') bytes)"
