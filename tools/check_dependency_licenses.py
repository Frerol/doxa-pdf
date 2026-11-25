#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Check the license metadata of the resolved pub or Android debug graph."""

import argparse
import hashlib
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urljoin, urlsplit
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PUB_LICENSES = ROOT / "tools/pub_licenses.tsv"
# Match known license URLs, ignoring the scheme and optional trailing slash.
MAVEN_LICENSE_URLS = {
    "www.apache.org/licenses/LICENSE-2.0": "Apache-2.0",
    "www.apache.org/licenses/LICENSE-2.0.txt": "Apache-2.0",
    "opensource.org/licenses/MIT": "MIT",
    "opensource.org/licenses/BSD-2-Clause": "BSD-2-Clause",
    "opensource.org/licenses/BSD-3-Clause": "BSD-3-Clause",
    "www.gnu.org/licenses/gpl-3.0": "GPL-3.0",
    "www.gnu.org/licenses/lgpl-3.0": "LGPL-3.0",
}
FLUTTER_DEBUG_MODULES = {
    "io.flutter:arm64_v8a_debug",
    "io.flutter:armeabi_v7a_debug",
    "io.flutter:flutter_embedding_debug",
    "io.flutter:x86_64_debug",
}
MAVEN_INHERITED_LICENSES = {
    # The artifact's POM inherits this from guava-parent:26.0-android.
    # https://repo.maven.apache.org/maven2/com/google/guava/guava-parent/26.0-android/guava-parent-26.0-android.pom
    "com.google.guava:listenablefuture:1.0": "Apache-2.0",
}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def file_path(uri):
    return Path(unquote(urlsplit(uri).path)).resolve()


def license_digest(text):
    return hashlib.sha256(" ".join(text.split()).encode("utf-8")).hexdigest()


def pub_licenses():
    config = ROOT / ".dart_tool/package_config.json"
    packages = read_json(config)
    workspace = set(read_json(config.with_name("package_graph.json"))["roots"])
    flutter = file_path(packages["flutterRoot"])
    approved = {}
    for line in PUB_LICENSES.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            digest, label, _ = line.split("\t")
            approved[digest] = label

    licenses = {}
    for package in packages["packages"]:
        name = package["name"]
        root = file_path(urljoin(config.as_uri(), package["rootUri"]))
        if (name in workspace and root.is_relative_to(ROOT)) or root.is_relative_to(flutter):
            continue
        path = root / "LICENSE"
        if not path.is_file():
            licenses[name] = "missing LICENSE"
            continue
        digest = license_digest(path.read_text(encoding="utf-8"))
        licenses[name] = approved.get(digest, f"unreviewed LICENSE ({digest})")
    return licenses


def maven_license(path):
    if not path:
        return "missing Maven POM"
    project = ET.parse(path).getroot()
    declarations = project.findall("./{*}licenses/{*}license")
    if not declarations:
        return "missing Maven license declaration"
    labels = set()
    for entry in declarations:
        raw_url = entry.findtext("{*}url", "").strip()
        url = urlsplit(raw_url)
        label = MAVEN_LICENSE_URLS.get(url.netloc + url.path.rstrip("/"))
        if url.scheme not in {"http", "https"} or not label:
            return f"unreviewed Maven license {entry.findtext('{*}name', '')!r} ({raw_url})"
        labels.add(label)
    return " AND ".join(sorted(labels))


def gradle_licenses(report, flutter_root):
    # Flutter's Maven POMs omit license declarations. The corresponding pinned
    # engine source carries its BSD license and separate third-party notices.
    engine = (flutter_root / "bin/internal/engine.version").read_text().strip()
    flutter_version = f"1.0.0-{engine}"
    licenses = {}
    for coordinate, pom in read_json(report).items():
        module, version = coordinate.rsplit(":", 1)
        if module in FLUTTER_DEBUG_MODULES and version == flutter_version:
            licenses[coordinate] = "BSD-3-Clause"
        else:
            license_name = maven_license(pom)
            if license_name == "missing Maven license declaration":
                license_name = MAVEN_INHERITED_LICENSES.get(coordinate, license_name)
            licenses[coordinate] = license_name
    return licenses


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="ecosystem", required=True)
    commands.add_parser("pub")
    gradle = commands.add_parser("gradle")
    gradle.add_argument("report", type=Path)
    args = parser.parse_args()

    if args.ecosystem == "pub":
        report = pub_licenses()
    else:
        config = read_json(ROOT / ".dart_tool/package_config.json")
        report = gradle_licenses(args.report, file_path(config["flutterRoot"]))

    if not report:
        parser.error("The resolved dependency report is empty")
    errors = []
    for name, license_name in sorted(report.items()):
        if license_name.startswith(("missing ", "unreviewed ")):
            errors.append(f"{name}: {license_name}")
        else:
            print(f"{name}: {license_name}")
    for error in errors:
        print(error, file=sys.stderr)
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
