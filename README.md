# AppRunner CI

The public build and test pipeline for [AppRunner](https://github.com/Dospacite/apprunner).

AppRunner stores versioned Flutter project archives. This repository holds the
runner that fetches one with a private key and walks it through three gates, in
order, stopping at the first that fails:

```
flutter test  →  ios build  →  firebase xctest
```

No project source lives here. The workflow is dispatched with a run id, pulls
the archive over the API, and reports every transition back. That is why this
repository can be public — which matters, because **GitHub gives public
repositories free macOS minutes** and the iOS build needs macOS.

## Use it yourself

Create your own copy — you need one, because it holds your secrets and spends
your Actions minutes:

```bash
gh repo create apprunner-ci --public --template Dospacite/apprunner-ci
```

Then point your AppRunner server at it by setting `CI_REPO=your-name/apprunner-ci`
in the server's `.env`.

## Configuration

### Secrets

| Secret | Needed for | Notes |
| --- | --- | --- |
| `APPRUNNER_URL` | everything | Base URL of your control plane. |
| `APPRUNNER_KEY` | everything | A **pipeline** key from AppRunner → Settings. |
| `ASC_KEY_ID` | signing | App Store Connect key id. |
| `ASC_ISSUER_ID` | signing | Users and Access → Integrations. |
| `ASC_KEY_P8` | signing | The `.p8` file, base64 encoded. |
| `ASC_TEAM_ID` | signing | Apple team id. |
| `IOS_CERT_P12` | signing | Apple Development certificate **with private key**, base64. |
| `IOS_CERT_PASSWORD` | signing | Its export password. |
| `FIREBASE_SA` | Test Lab | GCP service account JSON. `setup-testlab.sh` installs it. |

### Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `IOS_ORG` | `com.example` | Reverse-DNS prefix for the bundle id. **Change it** — `com.example` cannot be signed. |
| `FIREBASE_PROJECT` | the service account's project | Only needed to override. |

## iOS signing

This is where the time goes, so here is what actually matters, learned the
expensive way:

**You must register at least one physical iOS device on your Apple team.**
XCTest requires the `get-task-allow` entitlement, and only *development* and
*ad-hoc* provisioning profiles allowlist it. Both embed device UDIDs, so both
require a registered device. App Store profiles need no device but disable
`get-task-allow`, so they cannot run tests. There is no device-free path.

Without a device you get `Communication with Apple failed: Your team has no
devices from which to generate a provisioning profile`, an unsigned bundle, and
then a bare `Test failed to run` from Test Lab that looks like a broken test but
is not.

Register one with the bundled helper:

```bash
export ASC_KEY_PATH=AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER_ID=<uuid>
../apprunner/tools/asc.py device-add <UDID> "CI" IOS
```

The UDID must be a real device's, in one of Apple's formats — `8 hex, dash,
16 hex` on current iPhones, or 40 hex characters on older ones. A UUID
(`8-4-4-4-12`) is a Mac or a Simulator and will be rejected. Find it in Finder
by clicking the text under a connected device's name.

The device never runs your tests; Test Lab re-signs for its own hardware. It
only has to exist so Apple will issue the profile.

Two smaller traps the workflow already handles:

- `xcodebuild archive` resolves the runner machine as a destination and demands
  *it* be registered, unless given `-destination 'generic/platform=iOS'`.
- `flutter build ios --config-only` runs its own signing check and refuses on a
  bare runner, so it is passed `--no-codesign`; xcodebuild signs afterwards.

Missing secrets degrade rather than break: without the `ASC_*` and `IOS_CERT_*`
set, the iOS stage still produces an unsigned `.app` and the device stage
reports itself skipped with the reason.

## Running it by hand

Actions → **Build and test** → **Run workflow**:

| Input | Meaning |
| --- | --- |
| `server_url` | Defaults to the `APPRUNNER_URL` secret. |
| `run_id` | Leave empty to build without reporting. |
| `project` | Slug or id. **Empty builds the newest archive you own.** |
| `skip_firebase` | `true` stops after the iOS build. Saves device quota. |
| `flutter_version` | Empty means latest stable. |
| `ios_device` | `model=…,version=…`. Empty picks the newest phone Test Lab offers. |

## What the runner does to a project

Anything the project already ships is used as-is. These are filled in only when
absent:

- **`ios/`** — generated when missing, or when present without a `RunnerTests`
  target.
- **`integration_test/`** — a launch smoke test is generated so the device stage
  has something to run. Ship your own and it is used instead.
- **Bundle identifier** — rewritten to `$IOS_ORG.<project>`, because
  `flutter create` defaults to `com.example.*`, which cannot be registered.
- **`RunnerTests`** — switched to integration_test's Objective-C runner macro,
  which reflects each Dart test into its own XCTest case so Test Lab reports
  them individually.

## Scripts

| Script | Job |
| --- | --- |
| `apprunner.sh` | Everything that talks to the control plane. No-ops without a run id. |
| `prepare_project.sh` | Brings a project up to the shape the iOS pipeline needs. |
| `patch_xcode.py` | Bundle ids and the Objective-C test runner, in `project.pbxproj`. |
| `build_ios.sh` | Unsigned `.app` always; a signed `.ipa` when signing works. |
| `build_testable.sh` | The XCTest bundle. Refuses to ship unsigned artifacts. |
| `run_testlab.sh` | Picks a device from the live catalogue and runs the bundle. |
| `summarize_*.sh` | Condense a log into the one line the pipeline rail shows. |

## Firebase quota

The free tier allows five physical-device tests per day. AppRunner counts
stages that actually started, so a run stopped at an earlier gate costs
nothing, and it pre-emptively skips the device stage once the budget is spent.
