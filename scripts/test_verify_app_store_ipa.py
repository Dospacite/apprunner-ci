#!/usr/bin/env python3

import pathlib
import plistlib
import tempfile
import unittest
import zipfile

from verify_app_store_ipa import verify_ipa


def make_ipa(path, *, get_task_allow=False, devices=None, sdk="iphoneos26.0"):
    info = {
        "CFBundleIdentifier": "com.rousoftware.rotationgame",
        "DTPlatformVersion": "26.0",
        "DTSDKName": sdk,
        "DTXcode": "2600",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "3",
        "UIDeviceFamily": [1, 2],
    }
    profile = {
        "Entitlements": {
            "application-identifier": "TEAM.com.rousoftware.rotationgame",
            "get-task-allow": get_task_allow,
        },
    }
    if devices:
        profile["ProvisionedDevices"] = devices
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("Payload/Runner.app/Info.plist", plistlib.dumps(info))
        archive.writestr("Payload/Runner.app/embedded.mobileprovision", plistlib.dumps(profile))


class VerifyAppStoreIpaTest(unittest.TestCase):
    def test_accepts_distribution_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = pathlib.Path(directory) / "Runner.ipa"
            make_ipa(ipa)
            verify_ipa(
                ipa,
                "com.rousoftware.rotationgame",
                require_codesign=False,
                required_device_families=(1, 2),
            )

    def test_rejects_development_profiles(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = pathlib.Path(directory) / "Runner.ipa"
            make_ipa(ipa, get_task_allow=True, devices=["device"])
            with self.assertRaisesRegex(ValueError, "development or enterprise"):
                verify_ipa(ipa, "com.rousoftware.rotationgame", require_codesign=False)

    def test_rejects_old_sdks(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = pathlib.Path(directory) / "Runner.ipa"
            make_ipa(ipa, sdk="iphoneos18.5")
            with self.assertRaisesRegex(ValueError, "iOS 26"):
                verify_ipa(ipa, "com.rousoftware.rotationgame", require_codesign=False)


if __name__ == "__main__":
    unittest.main()
