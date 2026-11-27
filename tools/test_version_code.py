# SPDX-License-Identifier: GPL-3.0-or-later

from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from version_code import check, version_code


class VersionCodeTest(unittest.TestCase):
    def test_grows_in_semver_order(self):
        # An upgrade installs only over a lower versionCode, so every step of
        # the release sequence (07-build-release.md §4) must grow.
        ordered = [
            "0.9.9",
            "1.0.0-alpha.1",
            "1.0.0-alpha.1.1",
            "1.0.0-alpha.1.9",
            "1.0.0-alpha.2",
            "1.0.0-alpha.9.9",
            "1.0.0-beta.1",
            "1.0.0-beta.9",
            "1.0.0-rc.1",
            "1.0.0-rc.9",
            "1.0.0",
            "1.0.1-alpha.1",
            "1.0.1",
            "1.0.99",
            "1.1.0-rc.1",
            "1.1.0",
            "1.99.99",
            "2.0.0-alpha.1",
        ]
        codes = [version_code(v) for v in ordered]
        self.assertEqual(codes, sorted(set(codes)))

    def test_rejects_what_the_scheme_cannot_order(self):
        for version in [
            "1.0",
            "v1.0.0",
            "1.0.0-alpha",
            "1.0.0-alpha.10",
            "1.0.0-alpha.0",
            "1.0.0-beta.1.1",
            "1.0.0-preview.1",
            "1.100.0",
            "1.0.100",
            "01.0.0",
        ]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                version_code(version)


class PubspecCheckTest(unittest.TestCase):
    def pubspec(self, version_line):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "pubspec.yaml"
        path.write_text(f"name: doxa_pdf\n{version_line}\nresolution: workspace\n")
        return path

    def test_build_number_must_be_the_derived_code(self):
        good = f"version: 1.0.0-alpha.1+{version_code('1.0.0-alpha.1')}"
        self.assertEqual(check(self.pubspec(good)), [])
        self.assertEqual(len(check(self.pubspec("version: 1.0.0-alpha.1+1"))), 1)
        self.assertEqual(len(check(self.pubspec("version: 1.0.0-alpha.1"))), 1)

    def test_tag_must_name_the_app_version(self):
        path = self.pubspec(f"version: 1.0.0-alpha.1+{version_code('1.0.0-alpha.1')}")
        self.assertEqual(check(path, tag="v1.0.0-alpha.1"), [])
        self.assertEqual(len(check(path, tag="v1.0.0-alpha.2")), 1)
        self.assertEqual(len(check(path, tag="1.0.0-alpha.1")), 1)


if __name__ == "__main__":
    unittest.main()
