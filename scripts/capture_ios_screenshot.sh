#!/usr/bin/env bash
# Build the Flutter app for an iOS simulator, launch it, and capture its first screen.
set -euo pipefail

APP_DIR="${1:?usage: capture_ios_screenshot.sh <app-dir> <bundle-id> <output.png>}"
BUNDLE_ID="${2:?usage: capture_ios_screenshot.sh <app-dir> <bundle-id> <output.png>}"
OUTPUT="${3:?usage: capture_ios_screenshot.sh <app-dir> <bundle-id> <output.png>}"
WAIT_SECONDS="${SCREENSHOT_WAIT_SECONDS:-8}"

log() { printf '[screenshot] %s\n' "$*" >&2; }

log "building the simulator application"
(
  cd "$APP_DIR"
  flutter build ios --simulator --release --no-codesign
)

APP_PATH="$APP_DIR/build/ios/iphonesimulator/Runner.app"
[[ -d "$APP_PATH" ]] || { log "simulator build not found at $APP_PATH"; exit 1; }

DEVICE_ID="$(python3 - <<'PY'
import json
import subprocess

catalogue = json.loads(subprocess.check_output(
    ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'],
    text=True,
))

devices = []
for runtime, entries in catalogue.get('devices', {}).items():
    if 'iOS' not in runtime:
        continue
    version = tuple(int(part) for part in runtime.rsplit('iOS-', 1)[-1].split('-'))
    for device in entries:
        if device.get('isAvailable') and device.get('name', '').startswith('iPhone'):
            devices.append((version, device['name'], device['udid']))

if not devices:
    raise SystemExit('no available iPhone simulator')

print(max(devices)[2])
PY
)"

STATE="$(xcrun simctl list devices --json | python3 -c '
import json, sys
target = sys.argv[1]
catalogue = json.load(sys.stdin)
for entries in catalogue.get("devices", {}).values():
    for device in entries:
        if device.get("udid") == target:
            print(device.get("state", "Shutdown"))
            raise SystemExit
' "$DEVICE_ID")"
STARTED_DEVICE=false

cleanup() {
  if [[ "$STARTED_DEVICE" == true ]]; then
    xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "$STATE" != "Booted" ]]; then
  log "booting simulator $DEVICE_ID"
  xcrun simctl boot "$DEVICE_ID"
  STARTED_DEVICE=true
fi
xcrun simctl bootstatus "$DEVICE_ID" -b

log "installing and launching $BUNDLE_ID"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch --terminate-running-process "$DEVICE_ID" "$BUNDLE_ID"
sleep "$WAIT_SECONDS"

mkdir -p "$(dirname "$OUTPUT")"
xcrun simctl io "$DEVICE_ID" screenshot "$OUTPUT"
[[ -s "$OUTPUT" ]] || { log "simctl did not produce a screenshot"; exit 1; }
log "wrote $OUTPUT"
