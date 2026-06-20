#!/usr/bin/env bash
# Export packages/scout_logger_plus → standalone GitHub repo directory.
#
#   SCOUT_PLATFORM_REPO=https://github.com/YOUR_ORG/scout-logger.git \
#     ./scripts/export-sdk-repo.sh ../scout_logger_plus
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/packages/scout_logger_plus"
TARGET="${1:-${ROOT}/../scout_logger_plus}"
PLATFORM_REPO="${SCOUT_PLATFORM_REPO:-https://github.com/YOUR_ORG/scout-logger.git}"

if [[ ! -d "$SRC/lib" ]]; then
  echo "Missing ${SRC}/lib — run from scout-logger repo with packages/scout_logger_plus present"
  exit 1
fi

echo "==> Exporting SDK to ${TARGET}"
mkdir -p "$TARGET"

rsync -a --delete \
  --exclude .dart_tool \
  --exclude build \
  --exclude '**/.dart_tool' \
  --exclude '**/build' \
  --exclude pubspec.lock \
  --exclude example/pubspec.lock \
  --exclude example/macos/Pods \
  --exclude example/macos/Flutter/ephemeral \
  --exclude example/ios/Pods \
  --exclude example/android/.gradle \
  "${SRC}/" "${TARGET}/"

cat > "${TARGET}/.gitignore" <<'EOF'
.env
.dart_tool/
.packages
build/
.flutter-plugins
.flutter-plugins-dependencies
pubspec.lock
example/pubspec.lock
example/.env
*.iml
.idea/
.vscode/
EOF

cat > "${TARGET}/pubspec.yaml" <<EOF
name: scout_logger_plus
description: Flutter client SDK for scout-logger — bridge apps to the dashboard via ingest API.
version: 0.2.0
publish_to: none

environment:
  sdk: ^3.5.0
  flutter: ">=3.19.0"

dependencies:
  flutter:
    sdk: flutter
  connectivity_plus: ^6.1.4
  devicelocale: ^0.8.1
  device_info_plus: ^11.5.0
  dio: ^5.9.0
  flutter_dotenv: ^5.2.1
  go_router: ^14.6.2
  meta: ^1.16.0
  package_info_plus: ^8.3.0
  scout_models:
    git:
      url: ${PLATFORM_REPO}
      path: packages/scout_models
  uuid: ^4.5.1
  path_provider: ^2.1.5

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
EOF

echo "==> Done. Next:"
echo "  cd ${TARGET}"
echo "  flutter pub get"
echo "  git init && git add . && git commit -m 'Initial scout_logger_plus'"
echo "  git remote add origin git@github.com:YOUR_ORG/scout_logger_plus.git"
