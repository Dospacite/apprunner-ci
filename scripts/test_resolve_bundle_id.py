#!/usr/bin/env python3

import pathlib
import tempfile
import unittest

from resolve_bundle_id import existing_bundle_id


class ResolveBundleIdTest(unittest.TestCase):
    def write_project(self, settings):
        temporary = tempfile.TemporaryDirectory()
        ios = pathlib.Path(temporary.name) / "ios"
        project = ios / "Runner.xcodeproj"
        project.mkdir(parents=True)
        (project / "project.pbxproj").write_text("\n".join(
            f"PRODUCT_BUNDLE_IDENTIFIER = {value};" for value in settings
        ))
        return temporary, ios

    def test_preserves_the_apps_explicit_identifier(self):
        temporary, ios = self.write_project([
            "com.rousoftware.rotationgame",
            "com.rousoftware.rotationgame.RunnerTests",
        ])
        with temporary:
            self.assertEqual(existing_bundle_id(ios), "com.rousoftware.rotationgame")

    def test_ignores_flutter_placeholder_identifiers(self):
        temporary, ios = self.write_project(["com.example.rotationGame"])
        with temporary:
            self.assertIsNone(existing_bundle_id(ios))


if __name__ == "__main__":
    unittest.main()
