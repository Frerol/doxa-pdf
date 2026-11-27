#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Write a CycloneDX 1.5 SBOM of what a release APK ships.

Components (docs/plan/07-build-release.md §4):
- pub packages the app depends on outside dev_dependencies, from
  `flutter pub deps --json` run in app/ (workspace packages are Doxa itself);
- the Android release runtime graph, from tools/gradle_license_report.init.gradle
  run with -PlicenseReportConfigurations=releaseRuntimeClasspath;
- the pinned PDFium binaries, from tools/pdfium.lock.

Licenses come from tools/check_dependency_licenses.py, so the SBOM names only
licenses that check has reviewed; anything else stops the script.

  tools/generate_sbom.py --version 1.0.0-alpha.1 \\
      --pub-deps pub-deps.json --gradle-report gradle.json --output sbom.cdx.json
"""

import argparse
import json
from pathlib import Path
import sys
import uuid

from check_dependency_licenses import (
    ROOT,
    file_path,
    gradle_licenses,
    pub_licenses,
    read_json,
)

APP = "doxa_pdf"
PDFIUM_LOCK = ROOT / "tools/pdfium.lock"


def shipped_pub_packages(deps):
    """Returns the packages of `pub deps --json` that the app ships, by name.

    Follows the app's non-dev dependencies; other workspace roots are Doxa's
    own packages and are followed but not listed.
    """
    packages = {package["name"]: package for package in deps["packages"]}
    if APP not in packages:
        raise ValueError(f"{APP} is not in the pub deps report")
    shipped, seen, pending = {}, set(), [APP]
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        seen.add(name)
        package = packages[name]
        if package["kind"] == "root":
            pending.extend(package["directDependencies"])
        else:
            shipped[name] = package
            pending.extend(package["dependencies"])
    return shipped


def pdfium_pin(path=PDFIUM_LOCK):
    """Returns (release, version) of the pinned PDFium binaries."""
    fields = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            key, value = line.split(maxsplit=1)
            fields[key] = value
    return fields["release"], fields["version"]


def _license(label):
    # Labels from check_dependency_licenses are SPDX ids joined by " AND ".
    if " " in label:
        return [{"expression": label}]
    return [{"license": {"id": label}}]


def sbom(version, pub_deps, pub_license_labels, gradle_license_labels, pdfium, flutter_version):
    """Returns the CycloneDX document; raises ValueError on an unreviewed license."""
    problems = []
    components = []

    for name, package in sorted(shipped_pub_packages(pub_deps).items()):
        if package["source"] == "sdk":
            # SDK packages are part of the pinned Flutter SDK (BSD-3-Clause).
            components.append({
                "type": "library",
                "bom-ref": f"pub:{name}",
                "name": name,
                "version": flutter_version,
                "group": "flutter-sdk",
                "licenses": _license("BSD-3-Clause"),
            })
            continue
        label = pub_license_labels.get(name, "missing LICENSE")
        if label.startswith(("missing ", "unreviewed ")):
            problems.append(f"pub {name}: {label}")
        purl = f"pkg:pub/{name}@{package['version']}"
        components.append({
            "type": "library",
            "bom-ref": purl,
            "name": name,
            "version": package["version"],
            "purl": purl,
            "licenses": _license(label),
        })

    for coordinate, label in sorted(gradle_license_labels.items()):
        if label.startswith(("missing ", "unreviewed ")):
            problems.append(f"gradle {coordinate}: {label}")
        group, name, module_version = coordinate.split(":")
        purl = f"pkg:maven/{group}/{name}@{module_version}"
        components.append({
            "type": "library",
            "bom-ref": purl,
            "group": group,
            "name": name,
            "version": module_version,
            "purl": purl,
            "licenses": _license(label),
        })

    release, pdfium_version = pdfium
    components.append({
        "type": "library",
        "bom-ref": "pdfium",
        "name": "pdfium",
        "version": pdfium_version,
        "description": "PDFium built without V8 and XFA; bundles third-party code "
        "whose license texts ship with the binaries and in the app's licenses screen.",
        "licenses": _license("BSD-3-Clause"),
        "externalReferences": [{
            "type": "distribution",
            "url": f"https://github.com/bblanchon/pdfium-binaries/releases/tag/{release}",
        }],
    })

    if problems:
        raise ValueError("\n".join(problems))
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, f'doxa-pdf/{version}')}",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "bom-ref": "doxa-pdf",
                "name": "Doxa PDF",
                "version": version,
                "licenses": _license("GPL-3.0-or-later"),
            },
        },
        "components": components,
    }


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--version", required=True)
    parser.add_argument("--pub-deps", type=Path, required=True)
    parser.add_argument("--gradle-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    pub_deps = read_json(args.pub_deps)
    flutter_version = next(
        sdk["version"] for sdk in pub_deps["sdks"] if sdk["name"] == "Flutter"
    )
    config = read_json(ROOT / ".dart_tool/package_config.json")
    try:
        document = sbom(
            args.version,
            pub_deps,
            pub_licenses(),
            gradle_licenses(args.gradle_report, file_path(config["flutterRoot"])),
            pdfium_pin(),
            flutter_version,
        )
    except ValueError as error:
        sys.exit(f"error: {error}")
    args.output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print(f"{args.output}: {len(document['components'])} components")


if __name__ == "__main__":
    main()
