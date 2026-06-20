#!/usr/bin/env bash
# First-time Hetzner setup (run once on the server via deploy, or manually over SSH).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Checking container runtime..."
if command -v podman >/dev/null 2>&1; then
  podman --version
  systemctl enable --now podman.socket 2>/dev/null || true
elif command -v docker >/dev/null 2>&1; then
  docker --version
else
  echo "Installing podman..."
  apt-get update -qq
  apt-get install -y podman podman-compose
  systemctl enable --now podman.socket
fi

if [[ ! -f .env ]]; then
  echo "Missing .env — deploy uploads it from your Mac."
  exit 1
fi

echo "==> Server bootstrap OK ($(pwd))"
