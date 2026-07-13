#!/usr/bin/env bash
# Production Flutter web build — no service-worker cache, versioned assets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DASH="${ROOT}/apps/dashboard"
cd "$DASH"

if [[ "${SKIP_FLUTTER_CLEAN:-0}" == "1" ]]; then
  echo "==> Skipping flutter clean (SKIP_FLUTTER_CLEAN=1)"
else
  echo "==> flutter clean"
  flutter clean
fi

flutter pub get

echo "==> flutter build web (release)"
flutter build web --release

line="$(grep '^version:' pubspec.yaml)"
if [[ "$line" =~ version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+) ]]; then
  ver="${BASH_REMATCH[1]}"
  build="${BASH_REMATCH[2]}"
else
  echo "pubspec version must be semver+build (e.g. 0.1.1+3)"
  exit 1
fi

WEB="${DASH}/build/web"
INDEX="${WEB}/index.html"
BOOT="${WEB}/flutter_bootstrap.js"

if [[ -f "$INDEX" ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then
    sed -i '' "s|flutter_bootstrap.js|flutter_bootstrap.js?v=${build}|g" "$INDEX"
  else
    sed -i "s|flutter_bootstrap.js|flutter_bootstrap.js?v=${build}|g" "$INDEX"
  fi
fi

if [[ -f "$BOOT" ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then
    sed -i '' "s|\"mainJsPath\":\"main.dart.js\"|\"mainJsPath\":\"main.dart.js?v=${build}\"|g" "$BOOT"
  else
    sed -i "s|\"mainJsPath\":\"main.dart.js\"|\"mainJsPath\":\"main.dart.js?v=${build}\"|g" "$BOOT"
  fi
fi

MAIN_JS="${WEB}/main.dart.js"
if [[ -f "$MAIN_JS" ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then
    sed -i '' -E "s|main\\.dart\\.js_([0-9]+)\\.part\\.js(\\?v=[0-9]+)?|main.dart.js_\\1.part.js?v=${build}|g" "$MAIN_JS"
  else
    sed -i -E "s|main\\.dart\\.js_([0-9]+)\\.part\\.js(\\?v=[0-9]+)?|main.dart.js_\\1.part.js?v=${build}|g" "$MAIN_JS"
  fi
fi

printf '{"app_name":"scout_dashboard","version":"%s","build_number":"%s","package_name":"scout_dashboard"}\n' "$ver" "$build" >"${WEB}/version.json"

rm -f "${WEB}/flutter_service_worker.js"

echo "==> Dashboard built ${ver}+${build} (cache-busted)"
