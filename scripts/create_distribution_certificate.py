#!/usr/bin/env python3
"""Create an Apple Distribution certificate and export a password-protected P12.

The App Store Connect API key and generated private key are never printed. The
private key exists only in a temporary directory; the P12 is the sole durable
private-key artifact.
"""

import argparse
import base64
import json
import os
import pathlib
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


API = "https://api.appstoreconnect.apple.com/v1/"


def required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"{name} is required")
    return value


def der_to_raw(der: bytes) -> bytes:
    if not der or der[0] != 0x30:
        raise ValueError("OpenSSL returned an invalid ES256 signature")
    offset = 2 + ((der[1] & 0x7F) if der[1] & 0x80 else 0)
    output = b""
    for _ in range(2):
        if der[offset] != 0x02:
            raise ValueError("OpenSSL returned an invalid ES256 integer")
        length = der[offset + 1]
        value = der[offset + 2 : offset + 2 + length].lstrip(b"\0").rjust(32, b"\0")
        output += value
        offset += 2 + length
    return output


def jwt(key_path: str, key_id: str, issuer_id: str) -> str:
    def encode(value: dict) -> bytes:
        return base64.urlsafe_b64encode(
            json.dumps(value, separators=(",", ":")).encode()
        ).rstrip(b"=")

    now = int(time.time())
    signing_input = b".".join(
        [
            encode({"alg": "ES256", "kid": key_id, "typ": "JWT"}),
            encode({"iss": issuer_id, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}),
        ]
    )
    signature = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input,
        capture_output=True,
        check=True,
    ).stdout
    return (
        signing_input
        + b"."
        + base64.urlsafe_b64encode(der_to_raw(signature)).rstrip(b"=")
    ).decode()


def create_certificate(token: str, csr: str) -> dict:
    body = {
        "data": {
            "type": "certificates",
            "attributes": {
                "certificateType": "DISTRIBUTION",
                "csrContent": csr,
            },
        }
    }
    request = urllib.request.Request(
        API + "certificates",
        method="POST",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response)["data"]
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        try:
            messages = json.loads(detail).get("errors", [])
            detail = "; ".join(
                f"{item.get('title')}: {item.get('detail')}" for item in messages
            )
        except json.JSONDecodeError:
            pass
        raise RuntimeError(f"App Store Connect returned HTTP {error.code}: {detail}") from error


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--metadata", required=True, type=pathlib.Path)
    args = parser.parse_args()

    key_path = required("ASC_KEY_PATH")
    key_id = required("ASC_KEY_ID")
    issuer_id = required("ASC_ISSUER_ID")
    password = required("P12_PASSWORD")

    with tempfile.TemporaryDirectory(prefix="apprunner-distribution-cert-") as directory:
        temporary = pathlib.Path(directory)
        private_key = temporary / "distribution.key"
        csr_path = temporary / "distribution.csr"
        certificate_der = temporary / "distribution.cer"
        certificate_pem = temporary / "distribution.pem"

        subprocess.run(
            [
                "openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
                "-keyout", str(private_key), "-out", str(csr_path),
                "-subj", "/CN=AppRunner Apple Distribution/",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        resource = create_certificate(jwt(key_path, key_id, issuer_id), csr_path.read_text())
        attributes = resource["attributes"]
        certificate_der.write_bytes(base64.b64decode(attributes["certificateContent"]))
        subprocess.run(
            [
                "openssl", "x509", "-inform", "DER", "-in", str(certificate_der),
                "-out", str(certificate_pem),
            ],
            check=True,
        )

        args.output.parent.mkdir(parents=True, exist_ok=True)
        environment = {**os.environ, "APPRUNNER_P12_PASSWORD": password}
        subprocess.run(
            [
                "openssl", "pkcs12", "-export", "-inkey", str(private_key),
                "-in", str(certificate_pem), "-out", str(args.output),
                "-name", "Apple Distribution", "-passout", "env:APPRUNNER_P12_PASSWORD",
            ],
            check=True,
            env=environment,
        )
        args.output.chmod(0o600)

    args.metadata.write_text(
        json.dumps(
            {
                "id": resource["id"],
                "certificateType": attributes.get("certificateType"),
                "displayName": attributes.get("displayName"),
                "serialNumber": attributes.get("serialNumber"),
                "platform": attributes.get("platform"),
                "expirationDate": attributes.get("expirationDate"),
            },
            indent=2,
        )
        + "\n"
    )
    print(f"Created {attributes.get('displayName', 'Apple Distribution certificate')}")


if __name__ == "__main__":
    main()
