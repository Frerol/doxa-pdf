#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Downloads the PDFium binaries pinned in tools/pdfium.lock, verifies their
# SHA-256 and lays them out under third_party/pdfium/ (git-ignored):
#
#   third_party/pdfium/include/                 headers (used by ffigen)
#   third_party/pdfium/linux-x64/lib/libpdfium.so
#   third_party/pdfium/jniLibs/<abi>/libpdfium.so   picked up by the Android build
#   third_party/pdfium/licenses/                third-party license texts
#
# Usage: tools/fetch_pdfium.sh [linux|android|all]   (default: all)
set -euo pipefail

cd "$(dirname "$0")/.."
LOCK=tools/pdfium.lock
OUT=third_party/pdfium
DL="$OUT/.downloads"
TARGET="${1:-all}"

release=$(awk '$1 == "release" { print $2 }' "$LOCK")
version=$(awk '$1 == "version" { print $2 }' "$LOCK")
base="https://github.com/bblanchon/pdfium-binaries/releases/download/${release/\//%2F}"

# Skip the work when the requested layout already matches the lock file.
stamp="$OUT/.stamp-$TARGET"
if [[ -f "$stamp" && "$(cat "$stamp")" == "$(sha256sum "$LOCK" | cut -d' ' -f1)" ]]; then
  echo "PDFium $version ($TARGET) is up to date."
  exit 0
fi

mkdir -p "$DL"

# fetch <asset> -> prints the extraction directory
fetch() {
  local asset=$1 sum dir
  sum=$(awk -v a="$asset" '$1 == a { print $2 }' "$LOCK")
  [[ -n "$sum" ]] || { echo "error: $asset is not pinned in $LOCK" >&2; exit 1; }
  if [[ ! -f "$DL/$asset" ]] || ! echo "$sum  $DL/$asset" | sha256sum -c --status; then
    echo "Downloading $asset ($release)..." >&2
    curl -fsSL --retry 3 -o "$DL/$asset.part" "$base/$asset"
    mv "$DL/$asset.part" "$DL/$asset"
  fi
  if ! echo "$sum  $DL/$asset" | sha256sum -c --status; then
    echo "error: checksum mismatch for $asset" >&2
    rm -f "$DL/$asset"
    exit 1
  fi
  dir="$DL/${asset%.tgz}"
  rm -rf "$dir" && mkdir -p "$dir"
  tar -xzf "$DL/$asset" -C "$dir"
  echo "$dir"
}

install_common() { # headers and licenses come from any archive
  local dir=$1
  rm -rf "$OUT/include" "$OUT/licenses"
  cp -r "$dir/include" "$OUT/include"
  rm -f "$OUT/include/"*.orig
  mkdir -p "$OUT/licenses" && cp -r "$dir/licenses/." "$OUT/licenses/" && cp "$dir/LICENSE" "$OUT/licenses/pdfium-LICENSE"
}

if [[ "$TARGET" == linux || "$TARGET" == all ]]; then
  dir=$(fetch pdfium-linux-x64.tgz)
  install_common "$dir"
  rm -rf "$OUT/linux-x64" && mkdir -p "$OUT/linux-x64/lib"
  cp "$dir/lib/libpdfium.so" "$OUT/linux-x64/lib/"
fi

if [[ "$TARGET" == android || "$TARGET" == all ]]; then
  for pair in arm64:arm64-v8a arm:armeabi-v7a x64:x86_64; do
    arch=${pair%%:*} abi=${pair#*:}
    dir=$(fetch "pdfium-android-$arch.tgz")
    [[ -d "$OUT/include" ]] || install_common "$dir"
    rm -rf "$OUT/jniLibs/$abi" && mkdir -p "$OUT/jniLibs/$abi"
    cp "$dir/lib/libpdfium.so" "$OUT/jniLibs/$abi/"
  done
fi

sha256sum "$LOCK" | cut -d' ' -f1 > "$stamp"
echo "PDFium $version ($TARGET) installed in $OUT/."
