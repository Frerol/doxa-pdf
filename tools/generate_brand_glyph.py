#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the Doxa brand SVGs from the pinned EB Garamond Italic delta."""

import argparse
from hashlib import sha256
from io import BytesIO
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

FONT_SHA256 = "bba2c4499c93c9612b90b9825d32b07da52fce2fe57562a1eb6b833553f93c4e"
BRAND = Path(__file__).resolve().parents[1] / "assets" / "brand"
HEADER = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <!-- SPDX-License-Identifier: GPL-3.0-or-later -->
  <!-- Doxa PDF icon. Outline derived from EB Garamond Italic, OFL 1.1. -->"""
ADAPTIVE_TRANSFORM = "translate(256 256) scale(0.68) translate(-256 -256)"


def svg_number(value):
    return f"{value:.3f}".rstrip("0").rstrip(".")


def delta_outline(data):
    with TTFont(BytesIO(data)) as variable_font:
        font = instantiateVariableFont(variable_font, {"wght": 600})
        glyphs = font.getGlyphSet()
        delta = glyphs[font.getBestCmap()[0x03B4]]
        bounds = BoundsPen(glyphs)
        delta.draw(bounds)
        left, bottom, right, top = bounds.bounds

        # The approved outline is 382 px tall and centred at (256, 251).
        scale = 382 / (top - bottom)
        transform = (
            scale, 0, 0, -scale,
            256 - scale * (left + right) / 2,
            60 + scale * top,
        )
        pen = SVGPathPen(glyphs, ntos=svg_number)
        delta.draw(TransformPen(pen, transform))
        return pen.getCommands()


def write_svg(filename, body):
    (BRAND / filename).write_text(f"{HEADER}\n{body}\n</svg>\n", encoding="utf-8", newline="\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, required=True)
    args = parser.parse_args()
    try:
        data = args.font.read_bytes()
    except OSError as error:
        parser.error(str(error))
    digest = sha256(data).hexdigest()
    if digest != FONT_SHA256:
        parser.error(f"font SHA-256 mismatch: expected {FONT_SHA256}, got {digest}")

    outline = delta_outline(data)
    # Paint the return first, then overlay the base, upper stem and hook tip.
    colour = f"""  <defs>
    <clipPath id="delta">
      <path d="{outline}"/>
    </clipPath>
  </defs>
  <g clip-path="url(#delta)">
    <rect width="512" height="512" fill="#F08C00"/>
    <path d="M276 256 L174 409 L0 512 H512 V0 H276 Z" fill="#7048E8"/>
    <path d="M0 0 H512 V251 L276 256 L272 218 H0 Z" fill="#2BAE66"/>
    <path d="M293 0 H512 V224 H316 Z" fill="#D6336C"/>
  </g>"""
    write_svg("doxa-glyph.svg", colour)
    write_svg("doxa-glyph-mono.svg", f'  <path d="{outline}" fill="#000"/>')
    indented_colour = "\n".join(f"  {line}" for line in colour.splitlines())
    write_svg(
        "doxa-adaptive-foreground.svg",
        f'  <g transform="{ADAPTIVE_TRANSFORM}">\n{indented_colour}\n  </g>',
    )
    for filename, background in (("doxa-icon.svg", "#161A23"), ("doxa-icon-light.svg", "#F5F6FA")):
        tile = f'  <rect width="512" height="512" rx="112" fill="{background}"/>'
        write_svg(filename, f"{tile}\n{colour}")


if __name__ == "__main__":
    main()
