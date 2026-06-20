#!/usr/bin/env bash
# Resolve docker/podman when not on PATH (common with Docker Desktop on macOS).

find_container_runtime() {
  if command -v docker >/dev/null 2>&1; then
    echo docker
    return 0
  fi
  if command -v podman >/dev/null 2>&1; then
    echo podman
    return 0
  fi
  local candidate
  for candidate in \
    /Applications/Docker.app/Contents/Resources/bin/docker \
    /usr/local/bin/docker \
    /opt/homebrew/bin/docker; do
    if [[ -x "$candidate" ]]; then
      export PATH="$(dirname "$candidate"):$PATH"
      echo docker
      return 0
    fi
  done
  return 1
}

require_container_runtime() {
  if ! find_container_runtime >/dev/null; then
    echo "Docker not found. Install Docker Desktop and start it:"
    echo "  https://www.docker.com/products/docker-desktop/"
    echo ""
    echo "Or add docker to PATH, then retry: ./dev docker"
    exit 1
  fi
}

compose_cmd() {
  require_container_runtime
  if command -v docker >/dev/null 2>&1; then
    docker compose "$@"
  else
    podman compose "$@"
  fi
}
