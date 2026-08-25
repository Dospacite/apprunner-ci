#!/usr/bin/env python3

import hashlib
import binascii
import json
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path


SCRIPT = Path(__file__).with_name("finalize_screenshots.py")


def png(width, height, suffix=b""):
    def chunk(kind, payload):
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
        )
    pixel = (suffix[:1] or b"\0") * 3
    rows = b"".join(b"\0" + pixel * width for _ in range(height))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


class FinalizeScreenshotsTest(unittest.TestCase):
    def test_writes_ordered_hashed_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            compact = output / "phones" / "compact"
            large = output / "phones" / "large"
            compact.mkdir(parents=True)
            large.mkdir(parents=True)
            for phone, width, height in [(compact, 750, 1334), (large, 1320, 2868)]:
                (phone / "question.png").write_bytes(png(width, height))
                (phone / "reveal.png").write_bytes(png(width, height, b"2"))
                (phone / "captures.json").write_text(json.dumps({
                    "version": 1,
                    "screenshots": [
                        {"name": "question", "ordinal": 0, "filename": "question.png"},
                        {"name": "reveal", "ordinal": 1, "filename": "reveal.png"},
                    ],
                }))
            (output / "resolved-phones.json").write_text(json.dumps([
                {"key": "compact", "ordinal": 0, "requested": {"kind": "preset", "preset": "compact"}, "model": "iPhone SE (3rd generation)", "runtime": "iOS 18.5"},
                {"key": "large", "ordinal": 1, "requested": {"kind": "preset", "preset": "large"}, "model": "iPhone 16 Pro Max", "runtime": "iOS 18.5"},
            ]))

            subprocess.run([str(SCRIPT), str(output)], check=True)

            manifest = json.loads((output / "manifest.json").read_text())
            self.assertEqual(manifest["version"], 2)
            self.assertEqual([phone["key"] for phone in manifest["phones"]], ["compact", "large"])
            self.assertEqual([item["name"] for item in manifest["phones"][0]["screenshots"]], ["question", "reveal"])
            question = manifest["phones"][0]["screenshots"][0]
            self.assertEqual((question["widthPixels"], question["heightPixels"]), (750, 1334))
            self.assertEqual(question["sha256"], hashlib.sha256(png(750, 1334)).hexdigest())
            self.assertFalse((compact / "captures.json").exists())

    def test_rejects_an_extra_png(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            phone = output / "phones" / "compact"
            phone.mkdir(parents=True)
            (phone / "question.png").write_bytes(png(750, 1334))
            (phone / "unexpected.png").write_bytes(png(750, 1334))
            (phone / "captures.json").write_text(json.dumps({
                "version": 1,
                "screenshots": [
                    {"name": "question", "ordinal": 0, "filename": "question.png"},
                ],
            }))
            (output / "resolved-phones.json").write_text(json.dumps([
                {"key": "compact", "ordinal": 0, "requested": {"kind": "preset", "preset": "compact"}, "model": "iPhone SE (3rd generation)", "runtime": "iOS 18.5"},
            ]))

            result = subprocess.run([str(SCRIPT), str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PNG set differs", result.stderr)

    def test_rejects_different_state_sequences(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            for key, name in [("compact", "question"), ("large", "reveal")]:
                phone = output / "phones" / key
                phone.mkdir(parents=True)
                (phone / f"{name}.png").write_bytes(png(750, 1334))
                (phone / "captures.json").write_text(json.dumps({
                    "version": 1,
                    "screenshots": [{"name": name, "ordinal": 0, "filename": f"{name}.png"}],
                }))
            (output / "resolved-phones.json").write_text(json.dumps([
                {"key": "compact", "ordinal": 0, "requested": {"kind": "preset", "preset": "compact"}, "model": "iPhone SE", "runtime": "iOS 18.5"},
                {"key": "large", "ordinal": 1, "requested": {"kind": "preset", "preset": "large"}, "model": "iPhone Pro Max", "runtime": "iOS 18.5"},
            ]))

            result = subprocess.run([str(SCRIPT), str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("same ordered states", result.stderr)


if __name__ == "__main__":
    unittest.main()
