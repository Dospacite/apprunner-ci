#!/usr/bin/env bash
# Run one app-owned Flutter screenshot journey on each requested iOS simulator.
set -euo pipefail

APP_DIR="${1:?usage: capture_ios_screenshots.sh <app-dir> <output-dir> [phones-json]}"
OUTPUT_DIR="${2:?usage: capture_ios_screenshots.sh <app-dir> <output-dir> [phones-json]}"
PHONES_JSON="${3:-[\"default\"]}"
SCENARIO="integration_test/apprunner_screenshots.dart"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '[screenshots] %s\n' "$*" >&2; }

if [[ ! -f "$APP_DIR/$SCENARIO" ]]; then
  log "Screenshot capture requested, but $SCENARIO is missing."
  log "Add that target and call binding.takeScreenshot('name') at each app-owned state."
  exit 1
fi

APP_DIR="$(cd "$APP_DIR" && pwd)"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/phones" "$APP_DIR/test_driver"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

python3 "$SCRIPT_DIR/resolve_ios_simulators.py" "$PHONES_JSON" > "$OUTPUT_DIR/resolved-phones.json"

STARTED_DEVICES=()
cleanup() {
  for device_id in "${STARTED_DEVICES[@]}"; do
    xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

cp "$SCRIPT_DIR/apprunner_screenshots_driver.dart" \
  "$APP_DIR/test_driver/apprunner_screenshots_driver.dart"

PHONE_COUNT="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$OUTPUT_DIR/resolved-phones.json")"
for ((index=0; index<PHONE_COUNT; index++)); do
  readarray -t PHONE < <(python3 -c '
import json, sys
phone = json.load(open(sys.argv[1]))[int(sys.argv[2])]
print(phone["key"])
print(phone["model"])
print(phone["runtime"])
print(phone["udid"])
' "$OUTPUT_DIR/resolved-phones.json" "$index")
  PHONE_KEY="${PHONE[0]}"
  MODEL="${PHONE[1]}"
  RUNTIME="${PHONE[2]}"
  DEVICE_ID="${PHONE[3]}"
  STATE="$(xcrun simctl list devices --json | python3 -c '
import json, sys
target = sys.argv[1]
for entries in json.load(sys.stdin).get("devices", {}).values():
    for device in entries:
        if device.get("udid") == target:
            print(device.get("state", "Shutdown"))
            raise SystemExit
' "$DEVICE_ID")"
  if [[ "$STATE" != "Booted" ]]; then
    log "booting $PHONE_KEY: $MODEL, $RUNTIME"
    xcrun simctl boot "$DEVICE_ID"
    STARTED_DEVICES+=("$DEVICE_ID")
  fi
  xcrun simctl bootstatus "$DEVICE_ID" -b

  PHONE_DIR="$OUTPUT_DIR/phones/$PHONE_KEY"
  mkdir -p "$PHONE_DIR"
  log "running $SCENARIO on $PHONE_KEY: $MODEL, $RUNTIME"
  (
    cd "$APP_DIR"
    APPRUNNER_SCREENSHOT_DIR="$PHONE_DIR" \
      flutter drive --debug \
        --device-id "$DEVICE_ID" \
        --target "$SCENARIO" \
        --driver test_driver/apprunner_screenshots_driver.dart
  )
done

python3 "$SCRIPT_DIR/finalize_screenshots.py" "$OUTPUT_DIR"
log "captured $(find "$OUTPUT_DIR/phones" -name '*.png' | wc -l | tr -d ' ') screens on $PHONE_COUNT phones"
