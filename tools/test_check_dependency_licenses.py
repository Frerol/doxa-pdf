# SPDX-License-Identifier: GPL-3.0-or-later

import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from check_dependency_licenses import gradle_licenses, license_digest, maven_license


class DependencyLicenseTest(unittest.TestCase):
    def setUp(self):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def write_pom(self, licenses):
        pom = self.root / "test.pom"
        pom.write_text(
            '<project xmlns="http://maven.apache.org/POM/4.0.0">'
            f"<licenses>{licenses}</licenses></project>",
            encoding="utf-8",
        )
        return pom

    def test_pub_digest_ignores_whitespace_but_covers_all_terms(self):
        approved = license_digest("example\nlicense")
        self.assertEqual(license_digest("example   license\r\n"), approved)
        self.assertNotEqual(license_digest("example license\nNon-commercial only"), approved)

    def test_maven_rejects_unknown_license_even_alongside_compatible_one(self):
        apache = "<license><url>https://www.apache.org/licenses/LICENSE-2.0</url></license>"
        self.assertEqual(maven_license(self.write_pom(apache)), "Apache-2.0")
        unknown = "<license><name>Non-commercial</name><url>https://example.org</url></license>"
        self.assertIn("unreviewed Maven license", maven_license(self.write_pom(apache + unknown)))

    def test_maven_fallbacks_are_limited_to_reviewed_artifacts(self):
        flutter_internal = self.root / "bin/internal"
        flutter_internal.mkdir(parents=True)
        (flutter_internal / "engine.version").write_text("engine123\n", encoding="utf-8")
        report = self.root / "report.json"
        missing = str(self.write_pom(""))
        report.write_text(json.dumps({
            "com.google.guava:listenablefuture:1.0": missing,
            "com.google.guava:listenablefuture:2.0": missing,
            "io.flutter:flutter_embedding_debug:1.0.0-engine123": missing,
            "io.flutter:flutter_embedding_debug:1.0.0-other": missing,
            "unreviewed:artifact:1.0": None,
        }), encoding="utf-8")

        self.assertEqual(gradle_licenses(report, self.root), {
            "com.google.guava:listenablefuture:1.0": "Apache-2.0",
            "com.google.guava:listenablefuture:2.0": "missing Maven license declaration",
            "io.flutter:flutter_embedding_debug:1.0.0-engine123": "BSD-3-Clause",
            "io.flutter:flutter_embedding_debug:1.0.0-other": "missing Maven license declaration",
            "unreviewed:artifact:1.0": "missing Maven POM",
        })


if __name__ == "__main__":
    unittest.main()
