// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// How pages are tinted for comfortable reading (FR-VIEW-005, FR-VIEW-016).
enum PageColorMode { normal, night, sepia, custom }

/// Paper colour of the sepia mode.
const sepiaPaper = Color(0xFFF4E8D0);

/// Default colours of the custom mode: light text on a dark blue-grey page.
const defaultCustomBackground = Color(0xFF1E2A33);
const defaultCustomText = Color(0xFFE6E1D3);

/// The filter that tints rendered pages for [mode], or null for normal.
///
/// The filters work on the rendered tiles, so switching mode only repaints:
/// nothing is rendered again (switching is instant).
/// - Night inverts brightness but rotates hues back, so a red figure stays
///   red-ish instead of turning cyan (the "image-aware where possible" of
///   FR-VIEW-005; photos still look inverted).
/// - Sepia multiplies the page by a paper colour, keeping every colour.
/// - Custom maps white to [background] and black to [text] by luminance
///   (FR-VIEW-016).
ColorFilter? pageColorFilter(
  PageColorMode mode, {
  Color background = defaultCustomBackground,
  Color text = defaultCustomText,
}) => switch (mode) {
  PageColorMode.normal => null,
  PageColorMode.night => const ColorFilter.matrix(nightMatrix),
  PageColorMode.sepia => ColorFilter.matrix(_multiply(sepiaPaper)),
  PageColorMode.custom => ColorFilter.matrix(_duotone(text, background)),
};

/// Inverts and then rotates hues by 180°, so brightness flips and hues stay.
/// Rows of a 4 × 5 colour matrix (offsets in 0..255).
const nightMatrix = <double>[
  ..._nightRow0,
  ..._nightRow1,
  ..._nightRow2,
  0, 0, 0, 1, 0, //
];

// Hue rotation by 180° (luminance weights 0.213, 0.715, 0.072) applied to
// an inversion (-x + 255): M = R(180) * (-I), offset = R(180) * 255.
const _nightRow0 = <double>[
  0.574, -1.430, -0.144, 0, 255, //
];
const _nightRow1 = <double>[
  -0.426, -0.430, -0.144, 0, 255, //
];
const _nightRow2 = <double>[
  -0.426, -1.430, 0.856, 0, 255, //
];

List<double> _multiply(Color tint) => [
  tint.r, 0, 0, 0, 0, //
  0, tint.g, 0, 0, 0, //
  0, 0, tint.b, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Maps luminance 0 → [dark] and 255 → [light].
List<double> _duotone(Color dark, Color light) {
  List<double> row(double from, double to) {
    final span = to - from;
    return [0.2126 * span, 0.7152 * span, 0.0722 * span, 0, from * 255];
  }

  return [
    ...row(dark.r, light.r),
    ...row(dark.g, light.g),
    ...row(dark.b, light.b),
    0, 0, 0, 1, 0, //
  ];
}

/// Applies a 4 × 5 colour matrix to an opaque [color]; for tests and for
/// tinting the blank sheet drawn under pages that are still loading.
Color applyColorMatrix(List<double> m, Color color) {
  int channel(int row) {
    final v =
        m[row * 5] * color.r * 255 +
        m[row * 5 + 1] * color.g * 255 +
        m[row * 5 + 2] * color.b * 255 +
        m[row * 5 + 4];
    return math.max(0, math.min(255, v)).round();
  }

  return Color.fromARGB(255, channel(0), channel(1), channel(2));
}

/// The colour of a blank page sheet in [mode].
Color sheetColor(
  PageColorMode mode, {
  Color background = defaultCustomBackground,
}) => switch (mode) {
  PageColorMode.normal => const Color(0xFFFFFFFF),
  PageColorMode.night => applyColorMatrix(nightMatrix, const Color(0xFFFFFFFF)),
  PageColorMode.sepia => sepiaPaper,
  PageColorMode.custom => background,
};
