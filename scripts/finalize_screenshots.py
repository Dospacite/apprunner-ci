#!/usr/bin/env python3
"""Validate a completed driver capture and write its authoritative manifest."""

import hashlib
import json
import re
import sys
from pathlib import Path

NAME = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
PNG = b"\x89PNG\r\n\x1a\n"


def main() -> None:
    output = Path(sys.argv[1]).resolve()
    captures_path = output / "captures.json"
    if not captures_path.is_file():
        raise SystemExit("screenshot journey did not produce captures.json")

    payload = json.loads(captures_path.read_text())
    screenshots = payload.get("screenshots")
    if payload.get("version") != 1 or not isinstance(screenshots, list) or not screenshots:
        raise SystemExit("captures.json is not a non-empty version 1 capture list")

    expected = set()
    manifest = []
    for ordinal, item in enumerate(screenshots):
        name = item.get("name")
        filename = item.get("filename")
        if not isinstance(name, str) or not NAME.fullmatch(name):
            raise SystemExit(f"invalid screenshot name: {name!r}")
        if item.get("ordinal") != ordinal or filename != f"{name}.png":
            raise SystemExit(f"invalid screenshot entry for {name}")
        if filename in expected:
            raise SystemExit(f"duplicate screenshot: {filename}")
        expected.add(filename)

        data = (output / filename).read_bytes()
        if not data.startswith(PNG):
            raise SystemExit(f"{filename} is not a PNG")
        manifest.append({
            "name": name,
            "ordinal": ordinal,
            "filename": filename,
            "sizeBytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        })

    actual = {path.name for path in output.glob("*.png")}
    if actual != expected:
        raise SystemExit(f"PNG set differs from captures.json: expected {sorted(expected)}, got {sorted(actual)}")

    pending = output / "manifest.json.tmp"
    pending.write_text(json.dumps({"version": 1, "screenshots": manifest}, indent=2) + "\n")
    pending.replace(output / "manifest.json")
    captures_path.unlink()


if __name__ == "__main__":
    main()
