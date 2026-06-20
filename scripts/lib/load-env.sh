#!/usr/bin/env bash
# Source the project root .env into the current shell.
set -euo pipefail

load_env() {
  local root="${1:?project root required}"
  local env_file="${root}/.env"

  if [[ ! -f "$env_file" ]]; then
    echo "Missing ${env_file} — copy .env.example to .env and configure it."
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}
