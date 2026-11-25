#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo 'rsvg-convert is required to generate Doxa icons. Install the librsvg command-line tools and rerun this script.' >&2
  exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."
brand=assets/brand
res=app/android/app/src/main/res
flutter_brand=app/assets/brand

render() {
  local size=$1 output=$2
  shift 2
  rsvg-convert --width "$size" --height "$size" --output "$output" "$@"
}

# Apply the colour foreground's transform to the monochrome SVG.
scaled_mono() {
  sed -e '/^<svg /a\  <g transform="translate(256 256) scale(0.68) translate(-256 -256)">' \
      -e '/^<\/svg>/i\  </g>' "$brand/doxa-glyph-mono.svg"
}

# Clip the dark legacy artwork to the round launcher silhouette.
round_icon() {
  sed -e '/^<svg /a\  <defs><clipPath id="round"><circle cx="256" cy="256" r="256"/></clipPath></defs>\n  <g clip-path="url(#round)">' \
      -e '/^<\/svg>/i\  </g>' "$brand/doxa-icon.svg"
}

# Density multipliers in half steps (mdpi is 2/2, hdpi is 3/2).
for profile in mdpi:2 hdpi:3 xhdpi:4 xxhdpi:6 xxxhdpi:8; do
  density=${profile%:*}
  scale=${profile#*:}
  mipmap="$res/mipmap-$density"
  drawable="$res/drawable-$density"
  mkdir -p "$mipmap" "$drawable"
  render "$((48 * scale / 2))" "$mipmap/ic_launcher.png" "$brand/doxa-icon.svg"
  round_icon | render "$((48 * scale / 2))" "$mipmap/ic_launcher_round.png"
  render "$((108 * scale / 2))" "$mipmap/ic_launcher_foreground.png" "$brand/doxa-adaptive-foreground.svg"
  scaled_mono | render "$((108 * scale / 2))" "$mipmap/ic_launcher_monochrome.png"
  # A transparent 288 dp canvas with artwork inside the 192 dp splash mask.
  render "$((288 * scale / 2))" "$drawable/doxa_splash.png" "$brand/doxa-adaptive-foreground.svg"
done

mkdir -p "$flutter_brand/2.0x" "$flutter_brand/3.0x"
render 96 "$flutter_brand/doxa-glyph.png" "$brand/doxa-glyph.svg"
render 192 "$flutter_brand/2.0x/doxa-glyph.png" "$brand/doxa-glyph.svg"
render 288 "$flutter_brand/3.0x/doxa-glyph.png" "$brand/doxa-glyph.svg"
