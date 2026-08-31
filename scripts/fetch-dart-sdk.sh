#!/usr/bin/env bash
# Download Linux x64 Dart SDK for running health-check scripts in the server container.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/infra/dart-sdk"
ARCH="${DART_SDK_ARCH:-x64}"
VER="${DART_SDK_VERSION:-3.5.4}"

if [[ -f "${OUT}/bin/dart" ]]; then
  echo "==> Dart SDK already present at ${OUT}/bin/dart"
  if [[ "$(uname -s)" == "Linux" ]]; then
    "${OUT}/bin/dart" --version
  else
    echo "    (linux binary — bundled into server Docker image at /opt/dart/bin/dart)"
  fi
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

URL="https://storage.googleapis.com/dart-archive/channels/stable/release/${VER}/sdk/dartsdk-linux-${ARCH}-release.zip"
echo "==> Downloading Dart SDK ${VER} (linux/${ARCH})..."
curl -fsSL "$URL" -o "${TMP}/dart-sdk.zip"
rm -rf "$OUT"
mkdir -p "$OUT"
unzip -q "${TMP}/dart-sdk.zip" -d "${TMP}/extract"
mv "${TMP}/extract/dart-sdk/"* "$OUT"
echo "==> ${OUT}/bin/dart (linux/${ARCH})"
if [[ "$(uname -s)" == "Linux" ]]; then
  "${OUT}/bin/dart" --version
else
  echo "    (linux binary — bundled into server Docker image at /opt/dart/bin/dart)"
fi
