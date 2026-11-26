#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Check mechanical repository rules against tracked working-tree files."""

import argparse
import os
from pathlib import Path
import re
import subprocess


SPDX = "SPDX-License-Identifier: GPL-3.0-or-later"
SOURCE_SUFFIXES = {".dart", ".kt", ".kts", ".py", ".sh"}
SPDX_EXEMPT = {
    # Flutter app scaffold: workspace build layout and plugin loader settings.
    "app/android/build.gradle.kts",
    "app/android/settings.gradle.kts",
    # Flutter plugin scaffold: Gradle project name.
    "packages/doxa_platform/android/settings.gradle.kts",
}
SKIP_PREFIXES = (
    "app/lib/l10n/gen/",
    # drift_dev schema helpers, regenerated from app/drift_schemas/.
    "app/test/drift/library/generated/",
    "third_party/",
    "test_corpus/",
)
DART_RULES = (
    (
        "flutter-material",
        re.compile(r"""\b(?:import|export)\s+['"](package:flutter/material\.dart)['"]"""),
        "Use package:material_ui/material_ui.dart.",
    ),
    (
        "pdfium-incremental",
        re.compile(r"\bFPDF_INCREMENTAL\b"),
        "Use a full PDFium save (flags 0).",
    ),
    (
        "one-euro",
        re.compile(r"one[- ]?euro", re.IGNORECASE),
        "Use the smoothing options in ADR-0006.",
    ),
)
ALLOW = re.compile(r"(?:^|\s|;)\s*(?://|#|/\*|<!--)\s*doxa-rules: allow ([a-z-]+)\b")


def tracked_paths(root):
    output = subprocess.check_output(["git", "ls-files", "-z", "--deduplicate"], cwd=root)
    return [os.fsdecode(path) for path in output.split(b"\0") if path]


def forbidden_names(root, environ):
    names = re.split(r"[,\n]", environ.get("DOXA_FORBIDDEN_NAMES", ""))
    local_file = root / ".forbidden-names"
    if local_file.is_file():
        names.extend(
            line for line in local_file.read_text(encoding="utf-8").splitlines()
            if not line.lstrip().startswith("#")
        )
    return {name.strip().casefold() for name in names if name.strip()}


def violations(root, paths, names, targets=()):
    """Yield diagnostics for the supplied repository-relative paths."""
    for path in paths:
        if targets and not any(
            path == target or path.startswith(target + "/") for target in targets
        ):
            continue
        file = root / path
        if (
            path == "LICENSE"
            or path.startswith(SKIP_PREFIXES)
            or file.name.endswith((".g.dart", ".g.kt", ".g.swift"))
            or file.name.startswith("messages.g.")
            or file.is_symlink()
            or not file.is_file()
        ):
            continue
        data = file.read_bytes()
        if b"\0" in data:
            continue
        try:
            lines = data.decode("utf-8-sig").splitlines()
        except UnicodeDecodeError:
            continue

        allowed = [{match[1] for match in ALLOW.finditer(line)} for line in lines]
        if (
            file.suffix in SOURCE_SUFFIXES
            and path not in SPDX_EXEMPT
            and not any(SPDX in line for line in lines[:5])
            and not any("spdx" in rules for rules in allowed[:5])
        ):
            yield path, 1, "spdx", f"Add '{SPDX}' within the first five lines."

        if file.suffix == ".dart":
            # Joining preserves imports split across lines. Offsets are mapped
            # to the line where the forbidden URI or identifier starts.
            source = "\n".join(lines)
            for rule, pattern, message in DART_RULES:
                for number in sorted({
                    source.count("\n", 0, match.start(match.lastindex or 0)) + 1
                    for match in pattern.finditer(source)
                }):
                    if rule not in allowed[number - 1]:
                        yield path, number, rule, message

        if names:
            # No opt-out: AGENTS.md forbids the name everywhere, without exceptions.
            if any(name in path.casefold() for name in names):
                yield path, 0, "forbidden-name", "Rename the file with a generic description."
            for number, line in enumerate(lines, 1):
                if any(name in line.casefold() for name in names):
                    yield path, number, "forbidden-name", "Use a generic product description."


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="files or directories to scan")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    targets = [
        os.path.relpath(Path(path).resolve(), root).replace(os.sep, "/")
        for path in args.paths
    ]
    if "." in targets:
        targets = []
    names = forbidden_names(root, os.environ)
    if not names:
        print("Note: forbidden-name check skipped (no names configured).")
    failed = False
    for path, line, rule, message in violations(root, tracked_paths(root), names, targets):
        print(f"{path}:{line}: {rule}: {message}")
        failed = True
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
