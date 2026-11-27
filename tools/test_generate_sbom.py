# SPDX-License-Identifier: GPL-3.0-or-later

import unittest

from generate_sbom import sbom, shipped_pub_packages


def package(name, kind="transitive", deps=(), direct=None, dev=(), source="hosted"):
    entry = {
        "name": name,
        "version": "1.0.0",
        "kind": kind,
        "source": source,
        "dependencies": list(deps) + list(dev),
        "directDependencies": list(deps if direct is None else direct),
    }
    if kind == "root":
        entry["devDependencies"] = list(dev)
    return entry


# The app ships drift (and its sqlite3 dependency) and flutter; build_runner
# is a dev dependency whose graph must stay out of the SBOM, even where a
# workspace package shares part of it.
DEPS = {
    "packages": [
        package("doxa_pdf", "root", deps=["doxa_core", "drift", "flutter"], dev=["build_runner"]),
        package("doxa_core", "root", deps=["meta"], dev=["test"]),
        package("drift", deps=["sqlite3", "meta"]),
        package("sqlite3"),
        package("meta"),
        package("flutter", source="sdk", deps=["sky_engine"]),
        package("sky_engine", source="sdk"),
        package("build_runner", deps=["analyzer"]),
        package("analyzer", deps=["meta"]),
        package("test", deps=["analyzer"]),
    ],
}


class ShippedPackagesTest(unittest.TestCase):
    def test_follows_runtime_dependencies_and_drops_dev_graphs(self):
        self.assertEqual(
            sorted(shipped_pub_packages(DEPS)),
            ["drift", "flutter", "meta", "sky_engine", "sqlite3"],
        )


class SbomTest(unittest.TestCase):
    def build(self, pub=None, gradle=None):
        labels = {"drift": "MIT", "sqlite3": "MIT", "meta": "BSD-3-Clause"}
        labels.update(pub or {})
        return sbom(
            "1.0.0-alpha.1",
            DEPS,
            labels,
            gradle or {"androidx.core:core:1.13.0": "Apache-2.0"},
            ("chromium/8179", "160.0.8179.0"),
            "3.50.1",
        )

    def test_lists_pub_gradle_and_pdfium(self):
        names = {c["name"] for c in self.build()["components"]}
        self.assertEqual(
            names, {"drift", "sqlite3", "meta", "flutter", "sky_engine", "core", "pdfium"}
        )

    def test_refuses_unreviewed_licenses(self):
        with self.assertRaisesRegex(ValueError, "sqlite3"):
            self.build(pub={"sqlite3": "unreviewed LICENSE (abc)"})
        with self.assertRaisesRegex(ValueError, "androidx.core:core"):
            self.build(gradle={"androidx.core:core:1.13.0": "missing Maven POM"})


if __name__ == "__main__":
    unittest.main()
