# AppRunner CI

The public build and test pipeline for [AppRunner](https://apprunner.asgard.rousoftware.com).

AppRunner stores versioned Flutter project archives. This repository holds the
runner that fetches one with a private key and walks it through three gates, in
order, stopping at the first that fails:

```
flutter test  →  ios build  →  firebase xctest
```

Nothing about a project lives here. The workflow is dispatched with a run id,
pulls the archive over the API, and reports every transition back. That is why
this repository can be public while the projects it builds stay private.

## Running it

The workflow is normally dispatched by AppRunner when you press **Build and
test**. To run it by hand, use the Actions tab → **Build and test** → **Run
workflow**:

| Input | Meaning |
| --- | --- |
| `server_url` | AppRunner base URL. Defaults to the `APPRUNNER_URL` secret. |
| `run_id` | Run to report progress against. Leave empty to build without reporting. |
| `project` | Project slug or id. **Leave empty to build the newest archive you own.** |
| `skip_firebase` | `true` to stop after the iOS build. |
| `flutter_version` | Pin a Flutter version. Empty means latest stable. |
| `ios_device` | `model=…,version=…`. Empty picks the newest phone Test Lab offers. |

## Secrets

| Secret | Required for | Notes |
| --- | --- | --- |
| `APPRUNNER_URL` | everything | Base URL of the control plane. |
| `APPRUNNER_KEY` | everything | CI key from AppRunner → Settings. |
| `ASC_KEY_ID` | signing | App Store Connect key id. |
| `ASC_ISSUER_ID` | signing | App Store Connect issuer id. |
| `ASC_KEY_P8` | signing | The `.p8` file, base64 encoded. |
| `ASC_TEAM_ID` | signing | Apple team id. |
| `FIREBASE_SA` | Test Lab | GCP service account JSON with Test Lab Admin. |

Missing secrets degrade rather than break. Without the `ASC_*` set the iOS stage
still produces an unsigned build and an unsigned test bundle. Without
`FIREBASE_SA` the first two gates run normally and the device stage reports
itself skipped with the reason.

### On iOS signing

Automatic *development* signing needs a registered device, and GitHub's macOS
runners cannot register — Apple rejects their hostnames as too long for the
Device Name field, and burning a device slot per CI run would be wrong anyway.
So signing is attempted and never required:

- The downloadable `.app` is always built unsigned; a signed `.ipa` is exported
  on top only when signing succeeds.
- The XCTest bundle is signed when an identity exists and built **unsigned**
  otherwise. There is no middle ground: Apple rejects ad-hoc signing outright
  for the device SDK (*"Ad Hoc code signing is not allowed with SDK 'iOS 18.5'"*).
  Test Lab re-signs on upload but expects validly signed artifacts, so an
  unsigned bundle may be refused — the run says so rather than pretending.

To sign for real, give the runner a certificate:

```bash
# Export an Apple Development certificate + private key from Keychain as .p12
base64 -w0 cert.p12 | gh secret set IOS_CERT_P12 --repo Dospacite/apprunner-ci
gh secret set IOS_CERT_PASSWORD --repo Dospacite/apprunner-ci
```

The workflow imports it into a throwaway keychain, and automatic provisioning
then has the certificate it needs to build a profile from the ASC key.

The stage reports which path it took rather than claiming signing was
unconfigured.

## What the runner does to a project

Anything the project already ships is used as-is. These are filled in only when
absent:

- **`ios/`** — generated with `flutter create --platforms=ios` when the project
  has no iOS folder, or when it has one without a `RunnerTests` target.
- **`integration_test/`** — a launch smoke test is generated when the project
  has none, so the device stage has something to run. Ship your own and it is
  used instead. See the `flutter-testing` skill for how to write them.
- **Bundle identifier** — rewritten to `com.rousoftware.<project>`, because
  `flutter create` defaults to `com.example.*`, which cannot be registered for
  signing.
- **`RunnerTests`** — switched to integration_test's Objective-C runner macro,
  which reflects each Dart test into its own XCTest case so Test Lab reports
  them individually.

## Scripts

| Script | Job |
| --- | --- |
| `apprunner.sh` | Everything that talks to the control plane. No-ops without a run id. |
| `prepare_project.sh` | Brings a project up to the shape the iOS pipeline needs. |
| `patch_xcode.py` | Bundle ids and the Objective-C test runner, in `project.pbxproj`. |
| `build_ios.sh` | Unsigned `.app` always; a signed `.ipa` when signing is configured. |
| `build_testable.sh` | The XCTest bundle Test Lab consumes. |
| `run_testlab.sh` | Picks a device from the live catalogue and runs the bundle. |
| `summarize_*.sh` | Condense a log into the one line the pipeline rail shows. |

## Firebase quota

The free tier allows five physical-device tests per day. AppRunner counts
stages that actually started, so a run stopped at an earlier gate costs
nothing, and it pre-emptively skips the stage once the budget is spent.
