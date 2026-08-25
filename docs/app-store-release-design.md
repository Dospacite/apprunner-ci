# App Store release boundary

## Decision

AppRunner has two deliberately separate iOS outputs:

- The normal build produces an unsigned Release `Runner.app.zip`. It proves that
  the project compiles and is a test artifact only.
- An `appStoreRelease` run additionally produces a fail-closed IPA signed for
  App Store Connect. It never falls back to the unsigned or development build.

Firebase XCTest continues to use the existing Apple Development certificate.
The App Store lane uses a separate Apple Distribution certificate. A filename,
status message, or artifact kind must not imply that a test build is suitable
for submission.

## Usage

1. The caller requests `appStoreRelease: true` through the browser or MCP.
2. AppRunner preserves an existing non-placeholder Runner bundle identifier.
   A generated identifier is used only for a project without a usable one.
3. The macOS runner proves that Xcode 26+ and the iOS 26+ SDK are selected.
4. The normal compile and optional Firebase test bundle run as before.
5. `build_app_store.sh` archives with an Apple Distribution identity and exports
   with `method=app-store-connect`.
6. `verify_app_store_ipa.py` checks the signature, profile, entitlements,
   bundle identifier, Xcode, and SDK before publication.
7. Only a verified IPA is published as `ios-app-store`. Any store-lane failure
   fails the iOS stage and the run.

## Screenshot contract

Historical version 1 and 2 manifests remain readable. The existing selector
wire format gains two strict presets:

| Preset | Device class | Portrait pixels | Runtime |
| --- | --- | --- | --- |
| `iphone-6.9` | iPhone 16 Pro Max or newer verified Pro Max | 1320 x 2868 | iOS 26+ |
| `ipad-13` | iPad Pro 13-inch | 2064 x 2752 | iOS 26+ |

These store profiles do not fall back to a nearby simulator. Capture normalizes
their output through Core Graphics to opaque 8-bit RGB PNG, then both the runner
and server validate the complete PNG structure, dimensions, checksums, and a
one-to-ten image count. The app still owns state names, ordering, and content.

The database's existing `screenshot_phones_json` and artifact phone columns are
retained as storage compatibility details. Public text calls the new strict
targets store profiles; a broad persistence rename would add migration risk
without improving the release invariant.

## Interfaces and ownership

- `resolve_bundle_id.py(ios_dir, fallback) -> bundle id`: preserve app identity.
- `verify_apple_toolchain.sh`: fail unless Xcode and the iPhoneOS SDK meet the
  current submission floor.
- `build_ios.sh(app_dir) -> ios-test-build`: unsigned compile evidence only.
- `build_app_store.sh(app_dir, bundle_id) -> ios-app-store`: fail-closed export.
- `verify_app_store_ipa.py(ipa, bundle_id)`: artifact-level release proof.
- `resolve_ios_simulators.py(request, catalogue)`: resolve responsive presets,
  exact devices, and strict store profiles.
- `finalize_screenshots.py(output)`: authoritative capture/PNG manifest.

Rotation Game owns its bundle ID, version/build number, screenshot journey,
metadata, privacy answers, and upload order. AppRunner owns toolchain selection,
capture mechanics, technical image constraints, signing-lane separation, and
artifact verification.

## Required secrets

The existing `IOS_CERT_P12` and `IOS_CERT_PASSWORD` remain the Apple Development
identity used for Firebase. Store releases additionally require:

- `IOS_DISTRIBUTION_CERT_P12`
- `IOS_DISTRIBUTION_CERT_PASSWORD`

The existing App Store Connect API key secrets are shared by provisioning and
export. Missing or incorrect distribution credentials fail a requested store
release; they do not silently downgrade it.

## Rejected alternatives

- Converting the development export in place: breaks Firebase's signing needs
  and keeps one ambiguous artifact serving incompatible purposes.
- A second undispatched workflow: technically clean but not usable through the
  AppRunner control plane.
- Treating `large` as the App Store iPhone family: its selected model may drift
  and it has no exact pixel contract.
- Renaming every historical phone column and API in this release: high migration
  cost with no additional submission safety.
