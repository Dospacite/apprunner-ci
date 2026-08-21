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
        self.assertEqual([item["udid"] for item in resolved], ["se", "large"])

    def test_resolves_an_exact_model_and_runtime(self):
        result = self.run_resolver([{"key": "case", "model": "iPhone 15 Pro", "runtime": "17.5"}])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)[0]["udid"], "exact")

    def test_rejects_an_unavailable_exact_model(self):
        result = self.run_resolver([{"key": "case", "model": "iPhone 12 mini"}])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("available iPhones", result.stderr)


if __name__ == "__main__":
    unittest.main()
