#!/usr/bin/env bash
# Run an app-owned Flutter screenshot journey on one iOS simulator.
set -euo pipefail

APP_DIR="${1:?usage: capture_ios_screenshots.sh <app-dir> <output-dir>}"
OUTPUT_DIR="${2:?usage: capture_ios_screenshots.sh <app-dir> <output-dir>}"
SCENARIO="integration_test/apprunner_screenshots.dart"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '[screenshots] %s\n' "$*" >&2; }

if [[ ! -f "$APP_DIR/$SCENARIO" ]]; then
  log "Screenshot capture requested, but $SCENARIO is missing."
  log "Add that target and call binding.takeScreenshot('name') at each app-owned state."
  exit 1
fi

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
for entries in json.load(sys.stdin).get("devices", {}).values():
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

APP_DIR="$(cd "$APP_DIR" && pwd)"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR" "$APP_DIR/test_driver"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
cp "$SCRIPT_DIR/apprunner_screenshots_driver.dart" \
  "$APP_DIR/test_driver/apprunner_screenshots_driver.dart"

log "running $SCENARIO"
(
  cd "$APP_DIR"
  APPRUNNER_SCREENSHOT_DIR="$OUTPUT_DIR" \
    flutter drive --profile \
      --device-id "$DEVICE_ID" \
      --target "$SCENARIO" \
      --driver test_driver/apprunner_screenshots_driver.dart
)

python3 "$SCRIPT_DIR/finalize_screenshots.py" "$OUTPUT_DIR"
log "captured $(find "$OUTPUT_DIR" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ') screens"
