#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs the same checks as CI for the whole workspace:
# format, analyze, and the tests of every package and the app.
# Usage: tools/check.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# Prefer the FVM-pinned SDK when it is available.
if [[ -x .fvm/flutter_sdk/bin/flutter ]]; then
  export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"
fi

echo "==> flutter pub get"
flutter pub get >/dev/null

echo "==> dart format"
dart format --output=none --set-exit-if-changed .

echo "==> flutter analyze"
flutter analyze

# Pure Dart packages run with `dart test`; Flutter packages with `flutter test`.
for pkg in packages/*/ app/; do
  [[ -d "$pkg/test" ]] || continue
  echo "==> test $pkg"
  if grep -q 'sdk: flutter' "$pkg/pubspec.yaml"; then
    (cd "$pkg" && flutter test)
  else
    (cd "$pkg" && dart test)
  fi
done

echo "All checks passed."
