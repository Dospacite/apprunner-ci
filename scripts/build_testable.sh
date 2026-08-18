#!/usr/bin/env bash
#
# Produces the XCTest bundle Firebase Test Lab runs on a physical device.
#
# This follows Flutter's documented Test Lab recipe: point the Runner scheme at
# the integration test entrypoint with --config-only, build-for-testing against
# the device SDK, then zip the products directory together with its .xctestrun
# manifest. Test Lab reads that pair and needs nothing else.
#
# Usage: build_testable.sh <app-dir> <bundle-id>
# Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_TEAM_ID, KEY_PATH
set -euo pipefail

APP_DIR="${1:?usage: build_testable.sh <app-dir> <bundle-id>}"
BUNDLE_ID="${2:?usage: build_testable.sh <app-dir> <bundle-id>}"

: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${ASC_TEAM_ID:?ASC_TEAM_ID is required}"
: "${KEY_PATH:?KEY_PATH is required}"

log() { printf '\033[1;34m[testable]\033[0m %s\n' "$*" >&2; }
emit() { echo "$1" >> "${GITHUB_OUTPUT:-/dev/null}"; }

cd "$APP_DIR"

TARGET="$(ls integration_test/*.dart 2>/dev/null | head -1 || true)"
if [[ -z "$TARGET" ]]; then
  log "no integration test to build"
  emit "built=false"
  exit 1
fi
log "integration entrypoint: ${TARGET}"

# --config-only rewrites Generated.xcconfig so the Runner scheme launches the
# integration test rather than lib/main.dart. No compilation happens here.
flutter build ios --config-only --release "$TARGET"

log "building for testing against the device SDK"
( cd ios && xcodebuild build-for-testing \
    -workspace Runner.xcworkspace \
    -scheme Runner \
    -configuration Release \
    -derivedDataPath ../build/ios_integ \
    -sdk iphoneos \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    DEVELOPMENT_TEAM="$ASC_TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" )

PRODUCTS="build/ios_integ/Build/Products"
if [[ ! -d "$PRODUCTS" ]]; then
  log "no products directory at ${PRODUCTS}"
  emit "built=false"
  exit 1
fi

# Test Lab expects the device build directory and the .xctestrun manifest at
# the zip root, side by side.
XCTESTRUN="$(find "$PRODUCTS" -maxdepth 1 -name '*.xctestrun' | head -1)"
if [[ -z "$XCTESTRUN" ]]; then
  log "no .xctestrun manifest was produced"
  emit "built=false"
  exit 1
fi

log "zipping $(basename "$XCTESTRUN") with Release-iphoneos"
( cd "$PRODUCTS" && zip -qry "${OLDPWD}/build/ios_tests.zip" Release-iphoneos ./*.xctestrun )

if [[ ! -s build/ios_tests.zip ]]; then
  log "the test bundle is empty"
  emit "built=false"
  exit 1
fi

log "built build/ios_tests.zip ($(du -h build/ios_tests.zip | cut -f1))"
emit "built=true"
