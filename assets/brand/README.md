# Doxa PDF brand assets

The **provisional** identity: a lowercase delta (δ, for δόξα) drawn as one stroke in four study colours with hard joins.
Its bowl closes by passing under the stem. A fuller branding will come later ([UX §5](../../docs/plan/05-ux-design.md#5-visual-design)).

| File | Use |
|---|---|
| `doxa-icon.svg` | App icon on the dark background |
| `doxa-icon-light.svg` | App icon on a light background |
| `doxa-glyph.svg` | Transparent glyph for docs, the website and splash screens |
| `doxa-adaptive-foreground.svg` | Android adaptive icon foreground, scaled into the 66/108 safe zone |
| `doxa-glyph-mono.svg` | Single colour, for Android 13+ themed icons and notifications |
| `banner.png` | README header (1280×320) |
| `social-preview.png` | GitHub social preview (1280×640) |

| Colour | Hex |
|---|---|
| Magenta | `#D6336C` |
| Green | `#2BAE66` |
| Purple | `#7048E8` |
| Orange | `#F08C00` |
| Ink (background) | `#161A23` |
| Paper (light background) | `#F5F6FA` |

Keep the stroke order (magenta → green → purple → orange), the hard joins and the colours. Do not add gradients, outlines or effects.
The wordmark in the PNGs is set in Noto Sans (SIL Open Font License 1.1).

## Generated app assets

Run `tools/generate_android_icons.sh` from the repository root with `rsvg-convert`
from the librsvg command-line tools installed. All generated PNGs come from the
original Doxa SVGs in this directory and are GPL-3.0-or-later.

- [Android resources](../../app/android/app/src/main/res/) use
  `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}` for the launcher PNGs. Legacy icons
  use `doxa-icon.svg` at 48, 72, 96, 144 and 192 px, with a circular clip for
  the round variant. The adaptive foreground uses
  `doxa-adaptive-foreground.svg` at 108, 162, 216, 324 and 432 px. The
  monochrome layer uses `doxa-glyph-mono.svg` at the same sizes with the
  same centering transform and scale. Both sit over the Ink colour resource.
- The same transparent foreground is rendered to `drawable-*/doxa_splash.png`
  at 288, 432, 576, 864 and 1152 px. At 288 dp, the artwork fits inside the
  192 dp circle for an [Android splash icon without an icon background](https://developer.android.com/develop/ui/views/launch/splash-screen#dimensions).
  The system splash and the launch window both use Ink in light and dark modes.
- [Flutter assets](../../app/assets/brand/) use `doxa-glyph.svg` at 96, 192
  and 288 px for the home screen's 96 logical pixel glyph.
