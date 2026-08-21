#!/usr/bin/env python3
"""Validate a completed driver capture and write its authoritative manifest."""

import hashlib
import json
import re
import struct
import sys
from pathlib import Path

NAME = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
PNG = b"\x89PNG\r\n\x1a\n"


def read_capture(output, phone):
    key = phone["key"]
    captures_path = output / "phones" / key / "captures.json"
    if not captures_path.is_file():
        raise SystemExit(f"screenshot journey for {key} did not produce captures.json")
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

        source = captures_path.parent / filename
        data = source.read_bytes()
        if not data.startswith(PNG) or len(data) < 24 or data[12:16] != b"IHDR":
            raise SystemExit(f"{filename} is not a PNG")
        width, height = struct.unpack(">II", data[16:24])
        if width < 1 or height < 1:
            raise SystemExit(f"{filename} has invalid PNG dimensions")
        manifest.append({
            "name": name,
            "ordinal": ordinal,
            "filename": f"phones/{key}/{filename}",
            "widthPixels": width,
            "heightPixels": height,
            "sizeBytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        })

    actual = {path.name for path in captures_path.parent.glob("*.png")}
    if actual != expected:
        raise SystemExit(f"PNG set differs from captures.json: expected {sorted(expected)}, got {sorted(actual)}")
    captures_path.unlink()
    return manifest


def main() -> None:
    output = Path(sys.argv[1]).resolve()
    resolved_path = output / "resolved-phones.json"
    if not resolved_path.is_file():
        raise SystemExit("screenshot capture did not produce resolved-phones.json")
    phones = json.loads(resolved_path.read_text())
    if not isinstance(phones, list) or not phones:
        raise SystemExit("resolved-phones.json must contain at least one phone")

    manifest_phones = []
    state_sequence = None
    for ordinal, phone in enumerate(phones):
        key = phone.get("key")
        if phone.get("ordinal") != ordinal or not isinstance(key, str) or not NAME.fullmatch(key):
            raise SystemExit(f"invalid resolved phone at ordinal {ordinal}")
        screenshots = read_capture(output, phone)
        current = [(item["name"], item["ordinal"]) for item in screenshots]
        if state_sequence is None:
            state_sequence = current
        elif current != state_sequence:
            raise SystemExit("every screenshot phone must capture the same ordered states")
        manifest_phones.append({
            "key": key,
            "ordinal": ordinal,
            "requested": phone["requested"],
            "resolved": {"model": phone["model"], "runtime": phone["runtime"]},
            "screenshots": screenshots,
        })

    pending = output / "manifest.json.tmp"
    pending.write_text(json.dumps({"version": 2, "phones": manifest_phones}, indent=2) + "\n")
    pending.replace(output / "manifest.json")
    resolved_path.unlink()


if __name__ == "__main__":
    main()
