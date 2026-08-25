#!/usr/bin/env python3
"""Validate a completed driver capture and write its authoritative manifest."""

import hashlib
import binascii
import json
import re
import struct
import sys
import zlib
from pathlib import Path

NAME = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
PNG = b"\x89PNG\r\n\x1a\n"
STORE_PROFILES = {
    "iphone-6.9": (1320, 2868),
    "ipad-13": (2064, 2752),
}


def inspect_png(data, filename):
    if not data.startswith(PNG):
        raise SystemExit(f"{filename} is not a PNG")
    offset = len(PNG)
    chunks = []
    idat = bytearray()
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            raise SystemExit(f"{filename} has a truncated PNG chunk")
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length:end])[0]
        if binascii.crc32(kind + payload) & 0xFFFFFFFF != expected_crc:
            raise SystemExit(f"{filename} has an invalid PNG checksum")
        chunks.append((kind, payload))
        if kind == b"IDAT":
            idat.extend(payload)
        offset = end
        if kind == b"IEND":
            break
    if not chunks or chunks[0][0] != b"IHDR" or len(chunks[0][1]) != 13:
        raise SystemExit(f"{filename} has no valid IHDR")
    if chunks[-1][0] != b"IEND" or offset != len(data):
        raise SystemExit(f"{filename} has no terminal IEND chunk")
    try:
        decoded = zlib.decompress(bytes(idat))
    except zlib.error as error:
        raise SystemExit(f"{filename} has invalid compressed pixel data: {error}") from error
    width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunks[0][1])
    if width < 1 or height < 1 or compression != 0 or filtering != 0:
        raise SystemExit(f"{filename} has invalid PNG metadata")
    return width, height, bit_depth, color_type, interlace, chunks, decoded


def read_capture(output, phone):
    key = phone["key"]
    captures_path = output / "phones" / key / "captures.json"
    if not captures_path.is_file():
        raise SystemExit(f"screenshot journey for {key} did not produce captures.json")
    payload = json.loads(captures_path.read_text())
    screenshots = payload.get("screenshots")
    if payload.get("version") != 1 or not isinstance(screenshots, list) or not screenshots:
        raise SystemExit("captures.json is not a non-empty version 1 capture list")
    profile_key = phone.get("storeProfile", {}).get("key")
    if profile_key and not 1 <= len(screenshots) <= 10:
        raise SystemExit(f"store profile {profile_key} must contain between one and ten screenshots")

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
        width, height, bit_depth, color_type, interlace, chunks, decoded = inspect_png(data, filename)
        if profile_key:
            expected_width, expected_height = STORE_PROFILES[profile_key]
            if (width, height) != (expected_width, expected_height):
                raise SystemExit(
                    f"{filename} is {width}x{height}; {profile_key} requires {expected_width}x{expected_height}"
                )
            if bit_depth != 8 or color_type != 2 or interlace != 0:
                raise SystemExit(f"{filename} must be a non-interlaced 8-bit RGB PNG without alpha")
            if any(kind == b"tRNS" for kind, _ in chunks):
                raise SystemExit(f"{filename} contains PNG transparency")
            if len(decoded) != height * (1 + width * 3):
                raise SystemExit(f"{filename} has an invalid RGB scanline payload")
            stride = 1 + width * 3
            if any(decoded[row * stride] > 4 for row in range(height)):
                raise SystemExit(f"{filename} has an invalid PNG scanline filter")
        manifest.append({
            "name": name,
            "ordinal": ordinal,
            "filename": f"phones/{key}/{filename}",
            "widthPixels": width,
            "heightPixels": height,
            "bitDepth": bit_depth,
            "colorType": color_type,
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
            **({"storeProfile": phone["storeProfile"]} if "storeProfile" in phone else {}),
            "screenshots": screenshots,
        })

    pending = output / "manifest.json.tmp"
    pending.write_text(json.dumps({"version": 2, "phones": manifest_phones}, indent=2) + "\n")
    pending.replace(output / "manifest.json")
    resolved_path.unlink()


if __name__ == "__main__":
    main()
