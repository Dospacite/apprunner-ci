#!/usr/bin/env python3

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("resolve_ios_simulators.py")
CATALOGUE = {
    "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
            {"name": "iPhone SE (3rd generation)", "udid": "se", "isAvailable": True},
            {"name": "iPhone 16", "udid": "standard", "isAvailable": True},
            {"name": "iPhone 16 Pro Max", "udid": "large", "isAvailable": True},
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [
            {"name": "iPhone 15 Pro", "udid": "exact", "isAvailable": True},
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
            {"name": "iPhone 17 Pro Max", "udid": "store-phone", "isAvailable": True},
            {"name": "iPad Pro 13-inch (M4)", "udid": "store-ipad", "isAvailable": True},
        ],
    }
}


class ResolveIosSimulatorsTest(unittest.TestCase):
    def run_resolver(self, request):
        with tempfile.TemporaryDirectory() as directory:
            catalogue = Path(directory) / "catalogue.json"
            catalogue.write_text(json.dumps(CATALOGUE))
            return subprocess.run(
                [str(SCRIPT), json.dumps(request), str(catalogue)],
                capture_output=True,
                text=True,
            )

    def test_resolves_presets_in_request_order(self):
        result = self.run_resolver(["compact", "large"])
        self.assertEqual(result.returncode, 0, result.stderr)
        resolved = json.loads(result.stdout)
        self.assertEqual([item["key"] for item in resolved], ["compact", "large"])
        self.assertEqual([item["udid"] for item in resolved], ["se", "store-phone"])

    def test_resolves_an_exact_model_and_runtime(self):
        result = self.run_resolver([{"key": "case", "model": "iPhone 15 Pro", "runtime": "17.5"}])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)[0]["udid"], "exact")

    def test_rejects_an_unavailable_exact_model(self):
        result = self.run_resolver([{"key": "case", "model": "iPhone 12 mini"}])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("available devices", result.stderr)

    def test_resolves_strict_app_store_profiles(self):
        result = self.run_resolver(["iphone-6.9", "ipad-13"])
        self.assertEqual(result.returncode, 0, result.stderr)
        resolved = json.loads(result.stdout)
        self.assertEqual([item["udid"] for item in resolved], ["store-phone", "store-ipad"])
        self.assertEqual(resolved[0]["storeProfile"]["widthPixels"], 1320)
        self.assertEqual(resolved[1]["storeProfile"]["heightPixels"], 2752)


if __name__ == "__main__":
    unittest.main()
