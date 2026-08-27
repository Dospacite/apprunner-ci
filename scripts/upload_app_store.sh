#!/usr/bin/env bash
set -euo pipefail

IPA_PATH="${1:?usage: upload_app_store.sh <ipa>}"
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${KEY_PATH:?KEY_PATH is required}"

if [[ ! -s "$IPA_PATH" ]]; then
  echo "App Store IPA is missing or empty: $IPA_PATH" >&2
  exit 1
fi
if [[ ! -s "$KEY_PATH" ]]; then
  echo "App Store Connect key is missing or empty: $KEY_PATH" >&2
  exit 1
fi

echo "Uploading $(basename "$IPA_PATH") to App Store Connect." >&2
export API_PRIVATE_KEYS_DIR="$(dirname "$KEY_PATH")"
xcrun altool --upload-app \
  --file "$IPA_PATH" \
  --type ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" \
  --output-format json
echo "App Store Connect accepted the upload for processing." >&2
