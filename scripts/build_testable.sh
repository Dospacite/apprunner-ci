#!/usr/bin/env bash
#
# Produces the XCTest bundle Firebase Test Lab runs on a physical device.
#
# This follows Flutter's documented Test Lab recipe: point the Runner scheme at
# the integration test entrypoint with --config-only, build-for-testing against
# the device SDK, then zip the products directory together with its .xctestrun
# manifest. Test Lab reads that pair and needs nothing else.
#
# Signing, in order of preference:
#
#   1. A real identity in the keychain (import one via the IOS_CERT_P12 secret)
#      plus automatic provisioning from the App Store Connect key. This is the
#      only path that yields a bundle Test Lab is documented to accept.
#   2. Unsigned. Apple rejects ad-hoc signing outright for the device SDK
#      ("Ad Hoc code signing is not allowed with SDK 'iOS 18.5'"), so there is
#      no middle ground. Test Lab re-signs on upload but expects validly signed
#      artifacts, so an unsigned bundle may be refused — the stage says so
#      rather than pretending otherwise.
#
# Usage: build_testable.sh <app-dir> <bundle-id>
# Environment (optional): ASC_KEY_ID, ASC_ISSUER_ID, ASC_TEAM_ID, KEY_PATH
set -euo pipefail

APP_DIR="${1:?usage: build_testable.sh <app-dir> <bundle-id>}"
BUNDLE_ID="${2:?usage: build_testable.sh <app-dir> <bundle-id>}"

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
# integration test rather than lib/main.dart. No compilation happens here, but
# Flutter still refuses without a signing certificate unless told not to care —
# xcodebuild does the actual signing further down.
flutter build ios --config-only --release --no-codesign "$TARGET"

COMMON=(
  build-for-testing
  -workspace Runner.xcworkspace
  -scheme Runner
  -configuration Release
  -derivedDataPath ../build/ios_integ
  -sdk iphoneos
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
)

SIGNED=false
HAS_IDENTITY=false
if security find-identity -v -p codesigning 2>/dev/null | grep -qE '^[[:space:]]+[0-9]+\)'; then
  HAS_IDENTITY=true
fi

if [[ "$HAS_IDENTITY" == "true" && -n "${KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_TEAM_ID:-}" ]]; then
  log "attempting a signed build for team ${ASC_TEAM_ID}"
  if ( cd ios && xcodebuild "${COMMON[@]}" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$KEY_PATH" \
        -authenticationKeyID "$ASC_KEY_ID" \
        -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
        DEVELOPMENT_TEAM="$ASC_TEAM_ID" \
        CODE_SIGN_STYLE=Automatic ); then
    SIGNED=true
    log "signed build succeeded"
  else
    log "signed build failed; falling back to an unsigned bundle"
    rm -rf build/ios_integ
  fi
fi

if [[ "$SIGNED" != "true" ]]; then
  log "ERROR: signed XCTest build failed; refusing to submit unsigned artifacts to Test Lab"
  emit "built=false"
  emit "bundle_signed=false"
  exit 1
fi

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

APP="$(find "$PRODUCTS/Release-iphoneos" -maxdepth 1 -name '*.app' | head -1)"
if [[ -n "$APP" ]]; then
  if codesign --verify --deep "$APP" 2>&1; then
    log "codesign verifies $(basename "$APP")"
  else
    log "WARNING: $(basename "$APP") does not pass codesign --verify; Test Lab will reject it"
    emit "signature_valid=false"
  fi
fi

log "zipping $(basename "$XCTESTRUN") with Release-iphoneos"
( cd "$PRODUCTS" && zip -qry "${OLDPWD}/build/ios_tests.zip" Release-iphoneos ./*.xctestrun )

if [[ ! -s build/ios_tests.zip ]]; then
  log "the test bundle is empty"
  emit "built=false"
  exit 1
fi

log "built build/ios_tests.zip ($(du -h build/ios_tests.zip | cut -f1), signed=${SIGNED})"
emit "built=true"
emit "bundle_signed=${SIGNED}"
