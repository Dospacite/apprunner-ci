#!/usr/bin/env python3
"""Preserve a Flutter app's bundle id, using a generated fallback only for placeholders."""

import argparse
import collections
import pathlib
import re


BUNDLE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$")
SETTING = re.compile(r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);")


def existing_bundle_id(ios_dir: pathlib.Path) -> str | None:
    project = ios_dir / "Runner.xcodeproj" / "project.pbxproj"
    if not project.is_file():
        return None
    candidates = []
    for raw in SETTING.findall(project.read_text()):
        value = raw.strip().strip('"')
        if value.endswith(".RunnerTests"):
            value = value.removesuffix(".RunnerTests")
        if (
            BUNDLE_ID.fullmatch(value)
            and not value.startswith("com.example.")
            and "$" not in value
        ):
            candidates.append(value)
    if not candidates:
        return None
    return collections.Counter(candidates).most_common(1)[0][0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ios-dir", required=True, type=pathlib.Path)
    parser.add_argument("--fallback", required=True)
    args = parser.parse_args()
    if not BUNDLE_ID.fullmatch(args.fallback):
        raise SystemExit(f"invalid fallback bundle identifier: {args.fallback}")
    existing = existing_bundle_id(args.ios_dir)
    print(existing or args.fallback)


if __name__ == "__main__":
    main()
