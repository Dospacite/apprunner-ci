#!/usr/bin/env python3
"""Resolve public screenshot phone requests against a simctl catalogue."""

import json
import re
import subprocess
import sys
from pathlib import Path


PRESETS = {"default", "compact", "standard", "large"}
KEY = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")
VERSION = re.compile(r"^\d+\.\d+$")


def runtime_version(identifier):
    suffix = identifier.rsplit("iOS-", 1)[-1]
    parts = tuple(int(part) for part in suffix.split("-") if part.isdigit())
    return parts, ".".join(str(part) for part in parts)


def model_number(name):
    match = re.search(r"iPhone\s+(\d+)", name)
    return int(match.group(1)) if match else 0


def catalogue_phones(payload):
    phones = []
    for runtime_id, entries in payload.get("devices", {}).items():
        if "iOS-" not in runtime_id:
            continue
        version, display_version = runtime_version(runtime_id)
        for device in entries:
            name = device.get("name", "")
            if device.get("isAvailable") and name.startswith("iPhone"):
                phones.append({
                    "name": name,
                    "udid": device["udid"],
                    "runtime": f"iOS {display_version}",
                    "runtimeVersion": version,
                    "runtimeIdentifier": runtime_id,
                })
    return phones


def preset_candidates(preset, phones):
    if preset == "default":
        return phones
    if preset == "compact":
        return [phone for phone in phones if "iPhone SE" in phone["name"]]
    if preset == "large":
        return [phone for phone in phones if "Pro Max" in phone["name"] or " Plus" in phone["name"]]
    return [
        phone for phone in phones
        if "iPhone SE" not in phone["name"]
        and "Pro Max" not in phone["name"]
        and " Plus" not in phone["name"]
    ]


def rank(phone, preset):
    name = phone["name"]
    if preset == "default":
        return phone["runtimeVersion"], name
    family_rank = 1
    if preset == "large":
        family_rank = 2 if "Pro Max" in name else 1
    return family_rank, model_number(name), phone["runtimeVersion"], name


def normalize_request(raw):
    if not isinstance(raw, list) or not raw or len(raw) > 4:
        raise ValueError("screenshot phones must be a non-empty list of at most four entries")
    normalized = []
    keys = set()
    for ordinal, item in enumerate(raw):
        if isinstance(item, str):
            if item not in PRESETS:
                raise ValueError(f"unknown screenshot phone preset: {item}")
            key = item
            requested = {"kind": "preset", "preset": item}
        elif isinstance(item, dict):
            key = item.get("key")
            model = item.get("model")
            runtime = item.get("runtime")
            if not isinstance(model, str) or not model.strip():
                raise ValueError(f"exact screenshot phone at ordinal {ordinal} needs a model")
            if runtime is not None and (not isinstance(runtime, str) or not VERSION.fullmatch(runtime)):
                raise ValueError(f"invalid iOS runtime for screenshot phone {key}")
            requested = {"kind": "exact", "model": model.strip()}
            if runtime:
                requested["runtime"] = runtime
        else:
            raise ValueError(f"invalid screenshot phone at ordinal {ordinal}")
        if not isinstance(key, str) or not KEY.fullmatch(key):
            raise ValueError(f"invalid screenshot phone key: {key!r}")
        if key in keys:
            raise ValueError(f"duplicate screenshot phone key: {key}")
        keys.add(key)
        normalized.append({"key": key, "ordinal": ordinal, "requested": requested})
    return normalized


def resolve(request, catalogue):
    phones = catalogue_phones(catalogue)
    if not phones:
        raise ValueError("no available iPhone simulators")
    available = ", ".join(sorted({f'{p["name"]} ({p["runtime"]})' for p in phones}))
    resolved = []
    identities = set()
    for item in normalize_request(request):
        requested = item["requested"]
        if requested["kind"] == "preset":
            candidates = preset_candidates(requested["preset"], phones)
            preset = requested["preset"]
        else:
            candidates = [phone for phone in phones if phone["name"] == requested["model"]]
            if requested.get("runtime"):
                wanted = tuple(int(part) for part in requested["runtime"].split("."))
                candidates = [phone for phone in candidates if phone["runtimeVersion"][:2] == wanted]
            preset = "default"
        if not candidates:
            raise ValueError(f'could not resolve screenshot phone {item["key"]}; available iPhones: {available}')
        chosen = max(candidates, key=lambda phone: rank(phone, preset))
        identity = chosen["runtimeIdentifier"], chosen["udid"]
        if identity in identities:
            raise ValueError(f'screenshot phone {item["key"]} resolves to a simulator already selected')
        identities.add(identity)
        resolved.append({
            **item,
            "model": chosen["name"],
            "runtime": chosen["runtime"],
            "runtimeIdentifier": chosen["runtimeIdentifier"],
            "udid": chosen["udid"],
        })
    return resolved


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit("usage: resolve_ios_simulators.py <phones-json> [catalogue-json]")
    request = json.loads(sys.argv[1])
    if len(sys.argv) == 3:
        catalogue = json.loads(Path(sys.argv[2]).read_text())
    else:
        catalogue = json.loads(subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True,
        ))
    try:
        print(json.dumps(resolve(request, catalogue), indent=2))
    except ValueError as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()
