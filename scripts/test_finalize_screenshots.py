#!/usr/bin/env python3

import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("finalize_screenshots.py")
PNG = b"\x89PNG\r\n\x1a\nfixture"


class FinalizeScreenshotsTest(unittest.TestCase):
    def test_writes_ordered_hashed_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "question.png").write_bytes(PNG)
            (output / "reveal.png").write_bytes(PNG + b"2")
            (output / "captures.json").write_text(json.dumps({
                "version": 1,
                "screenshots": [
                    {"name": "question", "ordinal": 0, "filename": "question.png"},
                    {"name": "reveal", "ordinal": 1, "filename": "reveal.png"},
                ],
            }))

            subprocess.run([str(SCRIPT), str(output)], check=True)

            manifest = json.loads((output / "manifest.json").read_text())
            self.assertEqual([item["name"] for item in manifest["screenshots"]], ["question", "reveal"])
            self.assertEqual(manifest["screenshots"][0]["sha256"], hashlib.sha256(PNG).hexdigest())
            self.assertFalse((output / "captures.json").exists())

    def test_rejects_an_extra_png(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "question.png").write_bytes(PNG)
            (output / "unexpected.png").write_bytes(PNG)
            (output / "captures.json").write_text(json.dumps({
                "version": 1,
                "screenshots": [
                    {"name": "question", "ordinal": 0, "filename": "question.png"},
                ],
            }))

            result = subprocess.run([str(SCRIPT), str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PNG set differs", result.stderr)


if __name__ == "__main__":
    unittest.main()
