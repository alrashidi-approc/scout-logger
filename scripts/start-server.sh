#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -f "${ROOT}/.env" ]]; then
  echo "Copy ${ROOT}/.env.example to ${ROOT}/.env first."
  exit 1
fi

cd "${ROOT}/apps/server"
dart run bin/server.dart
