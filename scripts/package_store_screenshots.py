#!/usr/bin/env python3
"""Turn validated AppRunner captures into an upload-ordered App Store zip."""

import argparse
import json
import pathlib
import re
import shutil
import tempfile
import zipfile


NAME = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
FILENAME = re.compile(r"^\d{2}-[a-z0-9][a-z0-9_-]{0,50}\.png$")
PROFILES = {"iphone-6.9", "ipad-13"}


def package(capture_dir: pathlib.Path, spec_path: pathlib.Path, output_zip: pathlib.Path) -> None:
    spec = json.loads(spec_path.read_text())
    manifest = json.loads((capture_dir / "manifest.json").read_text())
    if spec.get("version") != 1 or spec.get("profiles") != ["iphone-6.9", "ipad-13"]:
        raise ValueError("store asset specification must request iphone-6.9 and ipad-13 in that order")
    entries = spec.get("screenshots")
    if not isinstance(entries, list) or not 1 <= len(entries) <= 10:
        raise ValueError("store asset specification must contain between one and ten screenshots")
    names = []
    filenames = []
    for index, entry in enumerate(entries, 1):
        name, filename = entry.get("name"), entry.get("filename")
        if not NAME.fullmatch(name or "") or not FILENAME.fullmatch(filename or ""):
            raise ValueError(f"invalid store screenshot entry at ordinal {index - 1}")
        if not filename.startswith(f"{index:02d}-"):
            raise ValueError("store screenshot filenames must have contiguous numeric prefixes")
        names.append(name)
        filenames.append(filename)
    if len(set(names)) != len(names) or len(set(filenames)) != len(filenames):
        raise ValueError("store screenshot names and filenames must be unique")

    phones = {phone.get("key"): phone for phone in manifest.get("phones", [])}
    if set(phones) != PROFILES:
        raise ValueError("capture must contain exactly the iphone-6.9 and ipad-13 store profiles")
    with tempfile.TemporaryDirectory(prefix="apprunner-store-screenshots-") as directory:
        root = pathlib.Path(directory)
        for profile in spec["profiles"]:
            screenshots = {item["name"]: item for item in phones[profile]["screenshots"]}
            if set(screenshots) != set(names):
                raise ValueError(f"{profile} capture states do not match the app-owned store specification")
            target_dir = root / profile
            target_dir.mkdir(parents=True)
            for name, filename in zip(names, filenames, strict=True):
                source = capture_dir / screenshots[name]["filename"]
                shutil.copyfile(source, target_dir / filename)
        (root / "manifest.json").write_text(json.dumps({
            "version": 1,
            "profiles": spec["profiles"],
            "screenshots": entries,
            "sourceManifest": "AppRunner screenshot manifest version 2",
        }, indent=2) + "\n")
        output_zip.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_STORED) as archive:
            for file in sorted(root.rglob("*")):
                if file.is_file():
                    archive.write(file, file.relative_to(root))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("capture_dir", type=pathlib.Path)
    parser.add_argument("spec", type=pathlib.Path)
    parser.add_argument("output_zip", type=pathlib.Path)
    args = parser.parse_args()
    try:
        package(args.capture_dir, args.spec, args.output_zip)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        raise SystemExit(f"App Store screenshot packaging failed: {error}") from error
    print(f"Packaged App Store screenshots: {args.output_zip}")


if __name__ == "__main__":
    main()
