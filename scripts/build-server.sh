#!/usr/bin/env bash
# Cross-compile scout server for Linux (run on Mac before deploy — avoids slow pub get on VPS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${SERVER_TARGET_ARCH:-x64}"

if ! command -v dart >/dev/null 2>&1; then
  echo "dart not found (install Flutter SDK or Dart SDK)"
  exit 1
fi

echo "==> Building server binary (linux/$ARCH)..."
(cd "${ROOT}/apps/server" && dart pub get && dart compile exe bin/server.dart -o server --target-os=linux --target-arch="$ARCH")
echo "==> ${ROOT}/apps/server/server"
