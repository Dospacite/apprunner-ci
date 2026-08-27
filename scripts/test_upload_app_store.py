import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("upload_app_store.sh")


class UploadAppStoreTest(unittest.TestCase):
    def test_uploads_ipa_with_api_key_authentication(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            ipa = root / "Runner.ipa"
            ipa.write_bytes(b"ipa")
            key_directory = root / "private_keys"
            key_directory.mkdir()
            key = key_directory / "AuthKey_TESTKEY.p8"
            key.write_text("private key", encoding="utf-8")
            capture = root / "capture.json"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            fake_xcrun = fake_bin / "xcrun"
            fake_xcrun.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "with open(os.environ['CAPTURE_PATH'], 'w', encoding='utf-8') as output:\n"
                "    json.dump({'args': sys.argv[1:], 'key_dir': os.environ.get('API_PRIVATE_KEYS_DIR')}, output)\n",
                encoding="utf-8",
            )
            fake_xcrun.chmod(0o755)

            environment = {
                **os.environ,
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "ASC_KEY_ID": "TESTKEY",
                "ASC_ISSUER_ID": "00000000-0000-0000-0000-000000000000",
                "KEY_PATH": str(key),
                "CAPTURE_PATH": str(capture),
            }
            result = subprocess.run(
                [str(SCRIPT), str(ipa)],
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            invocation = json.loads(capture.read_text(encoding="utf-8"))
            self.assertEqual(invocation["key_dir"], str(key_directory))
            self.assertEqual(
                invocation["args"],
                [
                    "altool",
                    "--upload-app",
                    "--file",
                    str(ipa),
                    "--type",
                    "ios",
                    "--apiKey",
                    "TESTKEY",
                    "--apiIssuer",
                    "00000000-0000-0000-0000-000000000000",
                    "--output-format",
                    "json",
                ],
            )

    def test_rejects_a_missing_ipa_before_calling_xcrun(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            key = root / "AuthKey_TESTKEY.p8"
            key.write_text("private key", encoding="utf-8")
            environment = {
                **os.environ,
                "ASC_KEY_ID": "TESTKEY",
                "ASC_ISSUER_ID": "00000000-0000-0000-0000-000000000000",
                "KEY_PATH": str(key),
            }

            result = subprocess.run(
                [str(SCRIPT), str(root / "missing.ipa")],
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("IPA is missing or empty", result.stderr)


if __name__ == "__main__":
    unittest.main()
