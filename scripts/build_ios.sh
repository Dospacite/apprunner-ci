#!/usr/bin/env bash
#
# Builds the iOS application and produces something downloadable.
#
# The unsigned .app always ships: it is what proves the project compiles for
# iOS, and it needs no Apple account to produce. A signed .ipa is attempted on
# top when signing is configured, but its failure does not close this gate —
# gate 2 asks "does this build for iOS", and the device stage does its own
# signing for the test bundle it actually needs.
#
# Usage: build_ios.sh <app-dir> <bundle-id>
# Environment: SIGNING, ASC_KEY_ID, ASC_ISSUER_ID, ASC_TEAM_ID, KEY_PATH
set -euo pipefail

APP_DIR="${1:?usage: build_ios.sh <app-dir> <bundle-id>}"
BUNDLE_ID="${2:?usage: build_ios.sh <app-dir> <bundle-id>}"
SIGNING="${SIGNING:-false}"

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

log "packaging Runner.app"
( cd build/ios/iphoneos && zip -qry "${OLDPWD}/build/Runner.app.zip" Runner.app )

if [[ "$SIGNING" != "true" ]]; then
  log "signing not configured; shipping the unsigned build"
  emit "signed=false"
  emit "sign_note=signing not configured"
  exit 0
fi

# ── Best-effort signed export ────────────────────────────────────────────────
: "${ASC_KEY_ID:?ASC_KEY_ID is required when SIGNING=true}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required when SIGNING=true}"
: "${ASC_TEAM_ID:?ASC_TEAM_ID is required when SIGNING=true}"
: "${KEY_PATH:?KEY_PATH is required when SIGNING=true}"

# Automatic signing can create a provisioning profile from the API key, but it
# cannot conjure a signing certificate into an empty keychain. Checking first
# turns a guaranteed three-minute failure into an immediate, accurate note.
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qE '^[[:space:]]+[0-9]+\)'; then
  log "no code signing identity in the runner keychain; skipping the signed export"
  emit "signed=false"
  emit "sign_note=no signing certificate on the runner"
  exit 0
fi

ARCHIVE="$PWD/build/Runner.xcarchive"

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>development</string>
  <key>teamID</key><string>${ASC_TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
  <key>compileBitcode</key><false/>
</dict>
</plist>
PLIST

# Flutter's own `build ipa` cannot pass App Store Connect credentials, so the
# archive is driven directly to hand xcodebuild the API key.
log "archiving with automatic signing for team ${ASC_TEAM_ID}"
# Without an explicit generic destination, xcodebuild resolves the runner
# machine as a concrete device and demands it be registered on the team
# ("Device 'sat12-...' isn't registered in your developer account").
if ! ( cd ios && xcodebuild archive \
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
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" ); then
  log "archive failed; keeping the unsigned build"
  emit "signed=false"
  emit "sign_note=archive failed, see the log"
  exit 0
fi

log "exporting the ipa"
if ! xcodebuild -exportArchive \
      -archivePath "$ARCHIVE" \
      -exportPath "$PWD/build/ipa" \
      -exportOptionsPlist build/ExportOptions.plist \
      -allowProvisioningUpdates \
      -authenticationKeyPath "$KEY_PATH" \
      -authenticationKeyID "$ASC_KEY_ID" \
      -authenticationKeyIssuerID "$ASC_ISSUER_ID"; then
  log "export failed; keeping the unsigned build"
  emit "signed=false"
  emit "sign_note=ipa export failed, see the log"
  exit 0
fi

IPA="$(find build/ipa -name '*.ipa' -maxdepth 1 | head -1)"
if [[ -n "$IPA" ]]; then
  mv "$IPA" build/Runner.ipa
  log "exported build/Runner.ipa"
  emit "signed=true"
else
  log "export produced no ipa; keeping the unsigned build"
  emit "signed=false"
  emit "sign_note=export produced no ipa"
fi
