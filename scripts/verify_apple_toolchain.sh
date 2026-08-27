#!/usr/bin/env bash
set -euo pipefail

MINIMUM_MAJOR="${MINIMUM_APP_STORE_SDK_MAJOR:-26}"
XCODE_OUTPUT="$(xcodebuild -version)"
XCODE_VERSION="$(sed -n 's/^Xcode //p' <<<"$XCODE_OUTPUT")"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
SDK_MAJOR="${SDK_VERSION%%.*}"

if [[ ! "$XCODE_MAJOR" =~ ^[0-9]+$ ]] || (( XCODE_MAJOR < MINIMUM_MAJOR )); then
  echo "App Store release requires Xcode ${MINIMUM_MAJOR}+; selected ${XCODE_VERSION:-unknown}." >&2
  exit 1
fi
if [[ ! "$SDK_MAJOR" =~ ^[0-9]+$ ]] || (( SDK_MAJOR < MINIMUM_MAJOR )); then
  echo "App Store release requires the iOS ${MINIMUM_MAJOR}+ SDK; selected ${SDK_VERSION:-unknown}." >&2
  exit 1
fi

echo "App Store toolchain: Xcode $XCODE_VERSION, iPhoneOS SDK $SDK_VERSION"
