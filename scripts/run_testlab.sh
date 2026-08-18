#!/usr/bin/env bash
#
# Runs the XCTest bundle on a physical device in Firebase Test Lab.
#
# Device models and the iOS versions they support rotate as Apple ships
# hardware, so a hardcoded model eventually starts failing with "unsupported
# device". The catalogue is queried at run time instead, and IOS_DEVICE
# overrides it when a specific device matters.
#
# Usage: run_testlab.sh <ios_tests.zip>
set -euo pipefail

BUNDLE="${1:?usage: run_testlab.sh <ios_tests.zip>}"
# Falls back to whatever project the service account authenticated as, so a
# self-hosted runner needs no extra configuration for the common case.
PROJECT="${FIREBASE_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" && "$PROJECT" != "(unset)" ]] || {
  echo "[testlab] set the FIREBASE_PROJECT repository variable, or authenticate a service account that names one" >&2
  exit 1
}
TIMEOUT="${TESTLAB_TIMEOUT:-15m}"

log() { printf '\033[1;33m[testlab]\033[0m %s\n' "$*" >&2; }

[[ -s "$BUNDLE" ]] || { log "missing or empty bundle: ${BUNDLE}"; exit 1; }

DEVICE="${IOS_DEVICE:-}"
if [[ -z "$DEVICE" ]]; then
  log "choosing a device from the Test Lab catalogue"
  CATALOGUE="$(gcloud firebase test ios models list --project "$PROJECT" --format=json)"
  DEVICE="$(python3 - "$CATALOGUE" <<'PY'
import json
import sys

models = json.loads(sys.argv[1])


def version_key(version_id):
    return tuple(int(part) for part in version_id.split('.') if part.isdigit())


candidates = []
for model in models:
    versions = model.get('supportedVersionIds') or []
    if not versions:
        continue
    # Phones only: the smoke test asserts a phone-shaped layout renders, and
    # phones are the cheapest slot in the free tier.
    if model.get('formFactor') not in (None, 'PHONE'):
        continue
    newest = max(versions, key=version_key)
    candidates.append((version_key(newest), model['id'], newest))

if not candidates:
    raise SystemExit('no usable device in the Test Lab catalogue')

# Newest OS wins; it is the configuration users are most likely on.
_, model_id, version_id = max(candidates)
print(f'model={model_id},version={version_id},locale=en_US,orientation=portrait')
PY
)"
fi

log "device: ${DEVICE}"
log "running the XCTest bundle (timeout ${TIMEOUT})"

# gcloud exits non-zero when a test case fails, which is exactly the signal the
# stage needs; no extra parsing required to decide pass or fail.
gcloud firebase test ios run \
  --project "$PROJECT" \
  --test "$BUNDLE" \
  --device "$DEVICE" \
  --timeout "$TIMEOUT"
