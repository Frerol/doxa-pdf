#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs the same checks as CI for the whole workspace:
# format, analyze, and the tests of every package and the app (with coverage).
#
# Usage:
#   tools/check.sh                 everything, as CI does; must pass before a PR
#   tools/check.sh <dir>...        only the given packages (for example
#                                  packages/doxa_dict app): format, analyze and
#                                  tests of those directories, without coverage.
#                                  A fast loop while working, not a PR check.
set -euo pipefail

cd "$(dirname "$0")/.."

# Prefer the FVM-pinned SDK when it is available.
if [[ -x .fvm/flutter_sdk/bin/flutter ]]; then
  export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"
fi

coverage=true
if (($# > 0)); then
  coverage=false
  targets=()
  for dir in "$@"; do
    dir="${dir%/}"
    if [[ ! -f "$dir/pubspec.yaml" ]]; then
      echo "error: $dir is not a package (no pubspec.yaml)" >&2
      exit 2
    fi
    targets+=("$dir")
  done
else
  targets=(.)
fi

echo "==> PDFium (Linux) for native tests"
tools/fetch_pdfium.sh linux

echo "==> flutter pub get"
flutter pub get >/dev/null

echo "==> dart format"
dart format --output=none --set-exit-if-changed "${targets[@]}"

echo "==> repository rules"
python3 tools/check_repo_rules.py "${targets[@]}"

echo "==> flutter analyze"
flutter analyze "${targets[@]}"

if [[ "${targets[*]}" == "." ]]; then
  packages=(packages/*/ app/)
else
  packages=("${targets[@]}")
fi

# Pure Dart packages run with `dart test`; Flutter packages with `flutter test`.
for pkg in "${packages[@]}"; do
  pkg="${pkg%/}"
  [[ -d "$pkg/test" ]] || continue
  echo "==> test $pkg"
  if grep -q 'sdk: flutter' "$pkg/pubspec.yaml"; then
    if $coverage; then
      (cd "$pkg" && flutter test --coverage)
    else
      (cd "$pkg" && flutter test)
    fi
  else
    if $coverage; then
      mkdir -p "$pkg/coverage"
      (cd "$pkg" && dart test --coverage-path=coverage/lcov.info)
    else
      (cd "$pkg" && dart test)
    fi
  fi
done

if $coverage; then
  echo "All checks passed."
else
  echo "Checks passed for: ${targets[*]} (scoped run; run tools/check.sh with no arguments before a PR)."
fi
