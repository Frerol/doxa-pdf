#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Derive and check the Android versionCode (docs/plan/07-build-release.md §4).

versionCode = MAJOR * 10_000_000 + MINOR * 100_000 + PATCH * 1_000 + stage,
where stage is 100 + 10 * N + F for alpha.N.F, 300 + N for beta.N,
500 + N for rc.N and 999 for a final release.

  tools/version_code.py 1.0.0-alpha.1      print the versionCode
  tools/version_code.py --check            check app/pubspec.yaml
  tools/version_code.py --check --tag v1.0.0-alpha.1
                                           also check that the tag names it
"""

import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PUBSPEC = ROOT / "app/pubspec.yaml"

_VERSION = re.compile(
    r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-(?:alpha\.([1-9])(?:\.([1-9]))?|beta\.([1-9])|rc\.([1-9])))?"
)


def version_code(version):
    """Returns the versionCode of [version], or raises ValueError."""
    match = _VERSION.fullmatch(version)
    if not match:
        raise ValueError(
            f"{version!r} is not MAJOR.MINOR.PATCH with an optional "
            "-alpha.N[.F], -beta.N or -rc.N (N, F from 1 to 9)"
        )
    major, minor, patch, alpha, fix, beta, rc = match.groups()
    if minor and int(minor) > 99 or patch and int(patch) > 99:
        raise ValueError(f"{version!r}: MINOR and PATCH must be at most 99")
    if alpha:
        stage = 100 + 10 * int(alpha) + int(fix or 0)
    elif beta:
        stage = 300 + int(beta)
    elif rc:
        stage = 500 + int(rc)
    else:
        stage = 999
    code = int(major) * 10_000_000 + int(minor) * 100_000 + int(patch) * 1_000 + stage
    if code > 2_100_000_000:
        raise ValueError(f"{version!r}: versionCode {code} is above Android's limit")
    return code


def pubspec_version(path=PUBSPEC):
    """Returns (name, build number) from the `version:` line of [path]."""
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"version:\s*([^\s+#]+)(?:\+(\d+))?\s*(?:#.*)?", line)
        if match:
            return match.group(1), match.group(2)
    raise ValueError(f"{path}: no version line")


def check(path=PUBSPEC, tag=None):
    """Returns the problems with [path]'s version, and with [tag] if given."""
    name, build = pubspec_version(path)
    try:
        expected = version_code(name)
    except ValueError as error:
        return [f"{path.name}: {error}"]
    problems = []
    if build != str(expected):
        problems.append(
            f"{path.name}: version {name}+{build} should be {name}+{expected}"
        )
    if tag is not None and tag != f"v{name}":
        problems.append(f"tag {tag} does not match the app version {name} (expected v{name})")
    return problems


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("version", nargs="?", help="a version such as 1.0.0-alpha.1")
    parser.add_argument("--check", action="store_true", help="check app/pubspec.yaml")
    parser.add_argument("--tag", help="with --check: the git tag being released")
    args = parser.parse_args()
    if args.check == (args.version is not None) or args.tag and not args.check:
        parser.error("give either a version or --check [--tag TAG]")
    if args.version is not None:
        try:
            print(version_code(args.version))
        except ValueError as error:
            sys.exit(f"error: {error}")
        return
    problems = check(tag=args.tag)
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
