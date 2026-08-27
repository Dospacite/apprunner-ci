#!/usr/bin/env bash
# Build and verify an App Store Connect IPA. This lane is intentionally fail-closed.
set -euo pipefail

APP_DIR="${1:?usage: build_app_store.sh <app-dir> <bundle-id> <build-number>}"
BUNDLE_ID="${2:?usage: build_app_store.sh <app-dir> <bundle-id> <build-number>}"
BUILD_NUMBER="${3:?usage: build_app_store.sh <app-dir> <bundle-id> <build-number>}"
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${ASC_TEAM_ID:?ASC_TEAM_ID is required}"
: "${KEY_PATH:?KEY_PATH is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_PATH="$APP_DIR/build/Runner-AppStore.ipa"
log() { printf '\033[1;35m[app-store]\033[0m %s\n' "$*" >&2; }
emit() { echo "$1" >> "${GITHUB_OUTPUT:-/dev/null}"; }

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  log "build number must be a positive integer"
  exit 1
fi

"$SCRIPT_DIR/verify_apple_toolchain.sh"
if ! security find-identity -v -p codesigning | grep -q '"Apple Distribution:'; then
  log "no Apple Distribution identity is available"
  exit 1
fi

cd "$APP_DIR"
mkdir -p build
ARCHIVE="$PWD/build/Runner-AppStore.xcarchive"
EXPORT_DIR="$PWD/build/app-store-export"

cat > build/ExportOptions-AppStore.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>${ASC_TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
  <key>uploadSymbols</key><true/>
</dict></plist>
PLIST

log "archiving $BUNDLE_ID for App Store Connect"
( cd ios && xcodebuild archive \
    -workspace Runner.xcworkspace \
    -scheme Runner \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    DEVELOPMENT_TEAM="$ASC_TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" )

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist build/ExportOptions-AppStore.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

IPA_COUNT="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' -type f | wc -l | tr -d ' ')"
if [[ "$IPA_COUNT" != "1" ]]; then
  log "export must produce exactly one IPA; found $IPA_COUNT"
  exit 1
fi
IPA="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' -type f -print -quit)"
mv "$IPA" build/Runner-AppStore.ipa
FAMILY_ARGS=(--require-device-family 1)
if [[ -f store-assets/apprunner_store_assets.json ]] \
   && python3 -c 'import json,sys; raise SystemExit("ipad-13" not in json.load(open(sys.argv[1])).get("profiles", []))' \
      store-assets/apprunner_store_assets.json; then
  FAMILY_ARGS+=(--require-device-family 2)
fi
python3 "$SCRIPT_DIR/verify_app_store_ipa.py" build/Runner-AppStore.ipa \
  --bundle-id "$BUNDLE_ID" "${FAMILY_ARGS[@]}"
emit "store_ready=true"
emit "artifact_path=$ARTIFACT_PATH"
emit "build_number=$BUILD_NUMBER"
log "verified build/Runner-AppStore.ipa as build $BUILD_NUMBER"
