#!/usr/bin/env python3
"""Fail closed unless an IPA has App Store distribution semantics."""

import argparse
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile


def major(value) -> int:
    match = re.search(r"(\d+)", str(value or ""))
    return int(match.group(1)) if match else 0


def decode_profile(path: pathlib.Path) -> dict:
    data = path.read_bytes()
    if data.startswith((b"<?xml", b"bplist")):
        return plistlib.loads(data)
    security = shutil.which("security")
    if not security:
        raise ValueError("security is required to decode embedded.mobileprovision")
    decoded = subprocess.check_output([security, "cms", "-D", "-i", str(path)])
    return plistlib.loads(decoded)


def read_codesign_entitlements(app: pathlib.Path) -> dict:
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", str(app)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    payload = result.stdout or result.stderr[result.stderr.find(b"<?xml") :]
    start = payload.find(b"<?xml")
    if start < 0:
        raise ValueError("codesign did not return app entitlements")
    return plistlib.loads(payload[start:])


def assert_distribution_entitlements(entitlements: dict, bundle_id: str, label: str) -> None:
    if entitlements.get("get-task-allow") is not False:
        raise ValueError(f"{label} must set get-task-allow=false")
    application_id = entitlements.get("application-identifier", "")
    if not application_id.endswith(f".{bundle_id}") or "*" in application_id:
        raise ValueError(f"{label} has a wildcard or mismatched application-identifier")


def verify_ipa(
    ipa: pathlib.Path,
    bundle_id: str,
    require_codesign: bool = True,
    required_device_families: tuple[int, ...] = (),
) -> None:
    if not zipfile.is_zipfile(ipa):
        raise ValueError("artifact is not an IPA zip")
    with tempfile.TemporaryDirectory(prefix="apprunner-ipa-") as directory:
        root = pathlib.Path(directory)
        with zipfile.ZipFile(ipa) as archive:
            archive.extractall(root)
        apps = list((root / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("IPA must contain exactly one Payload app")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != bundle_id:
            raise ValueError(
                f"bundle identifier is {info.get('CFBundleIdentifier')!r}; expected {bundle_id!r}"
            )
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            value = str(info.get(key, ""))
            if not value or "$" in value:
                raise ValueError(f"IPA has no resolved {key}")
        actual_families = set(info.get("UIDeviceFamily", []))
        missing_families = set(required_device_families) - actual_families
        if missing_families:
            raise ValueError(f"IPA is missing required device families: {sorted(missing_families)}")
        if major(info.get("DTPlatformVersion")) < 26 or major(info.get("DTSDKName")) < 26:
            raise ValueError("IPA was not built with the iOS 26 or newer SDK")
        if major(info.get("DTXcode")) < 2600:
            raise ValueError("IPA was not built with Xcode 26 or newer")

        profile_path = app / "embedded.mobileprovision"
        if not profile_path.is_file():
            raise ValueError("IPA has no embedded provisioning profile")
        profile = decode_profile(profile_path)
        if profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
            raise ValueError("IPA contains a development or enterprise provisioning profile")
        assert_distribution_entitlements(profile.get("Entitlements", {}), bundle_id, "profile")

        if require_codesign:
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
            details = subprocess.run(
                ["codesign", "-dvv", str(app)], capture_output=True, text=True, check=True
            ).stderr
            if "Authority=Apple Distribution:" not in details:
                raise ValueError("app is not signed by an Apple Distribution identity")
            assert_distribution_entitlements(read_codesign_entitlements(app), bundle_id, "app")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=pathlib.Path)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--require-device-family", action="append", type=int, default=[])
    args = parser.parse_args()
    try:
        verify_ipa(
            args.ipa,
            args.bundle_id,
            required_device_families=tuple(args.require_device_family),
        )
    except (OSError, ValueError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        print(f"App Store IPA verification failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
    print(f"Verified App Store IPA for {args.bundle_id}: {args.ipa}")


if __name__ == "__main__":
    main()
