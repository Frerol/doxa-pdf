#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
cd "$(dirname "$0")/.."

corpus=test_corpus
mkdir -p "$corpus/external"
scratch=$(mktemp -d "$corpus/external/.fetch.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

matches_checksum() {
  printf '%s  %s\n' "$1" "$2" | sha256sum --check --status
}

while IFS=$'\t' read -r path hash url _; do
  [[ "$path" == external/* && "$hash" != - ]] || continue
  target="$corpus/$path"
  if [[ -f "$target" ]] && matches_checksum "$hash" "$target"; then
    printf 'Verified %s\n' "$path"
    continue
  fi

  printf 'Downloading %s\n' "$path"
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error \
    --location --connect-timeout 20 --max-time 300 --retry 3 \
    --output "$scratch/download.pdf" "$url"
  if ! matches_checksum "$hash" "$scratch/download.pdf"; then
    printf 'SHA-256 mismatch for %s\n' "$path" >&2
    exit 1
  fi
  mv -f -- "$scratch/download.pdf" "$target"
done < "$corpus/MANIFEST"

# Chapter I spans PDF pages 68 through 103. Rasterizing removes the archive's
# OCR layer so the chapter can be used to measure OCR from page images.
gs -q -dBATCH -dNOPAUSE -dSAFER -sDEVICE=pdfimage8 -r300 -sCompression=Flate \
  -dFirstPage=68 -dLastPage=103 -sOutputFile="$scratch/scanned-chapter.pdf" \
  "$corpus/external/maxwell-treatise-scan.pdf"
mv -f -- "$scratch/scanned-chapter.pdf" "$corpus/external/scanned-chapter.pdf"
