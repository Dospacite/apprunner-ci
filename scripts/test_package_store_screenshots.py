#!/usr/bin/env python3

import json
import pathlib
import tempfile
import unittest
import zipfile

from package_store_screenshots import package


class PackageStoreScreenshotsTest(unittest.TestCase):
    def test_reorders_app_owned_states_for_both_profiles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            captures = root / "captures"
            phones = []
            for profile in ["iphone-6.9", "ipad-13"]:
                folder = captures / "phones" / profile
                folder.mkdir(parents=True)
                screenshots = []
                for ordinal, name in enumerate(["today", "rotation"]):
                    path = folder / f"{name}.png"
                    path.write_bytes(f"{profile}-{name}".encode())
                    screenshots.append({
                        "name": name,
                        "filename": f"phones/{profile}/{name}.png",
                        "ordinal": ordinal,
                    })
                phones.append({"key": profile, "screenshots": screenshots})
            (captures / "manifest.json").write_text(json.dumps({"version": 2, "phones": phones}))
            spec = root / "spec.json"
            spec.write_text(json.dumps({
                "version": 1,
                "profiles": ["iphone-6.9", "ipad-13"],
                "screenshots": [
                    {"name": "rotation", "filename": "01-rotation.png"},
                    {"name": "today", "filename": "02-today.png"},
                ],
            }))
            output = root / "store.zip"
            package(captures, spec, output)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(
                    archive.read("iphone-6.9/01-rotation.png"), b"iphone-6.9-rotation"
                )
                self.assertEqual(
                    archive.read("ipad-13/02-today.png"), b"ipad-13-today"
                )


if __name__ == "__main__":
    unittest.main()
