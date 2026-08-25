#!/usr/bin/env bash
#
# Builds the unsigned iOS test artifact that proves the project compiles.
# This output is never an App Store artifact. Distribution uses the separate,
# fail-closed build_app_store.sh lane.
#
# Usage: build_ios.sh <app-dir>
set -euo pipefail

APP_DIR="${1:?usage: build_ios.sh <app-dir>}"

log() { printf '\033[1;34m[build-ios]\033[0m %s\n' "$*" >&2; }
emit() { echo "$1" >> "${GITHUB_OUTPUT:-/dev/null}"; }

cd "$APP_DIR"
mkdir -p build

# ── The build that always runs ───────────────────────────────────────────────
log "building the release app (unsigned)"
flutter build ios --release --no-codesign

APP_PATH="build/ios/iphoneos/Runner.app"
if [[ ! -d "$APP_PATH" ]]; then
  log "expected $APP_PATH but it is missing"
  exit 1
fi

log "packaging the unsigned test build"
( cd build/ios/iphoneos && zip -qry "${OLDPWD}/build/Runner-Test.app.zip" Runner.app )
emit "artifact_path=$APP_DIR/build/Runner-Test.app.zip"
emit "artifact_kind=ios-test-build"
