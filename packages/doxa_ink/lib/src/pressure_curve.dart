// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

/// Pressure response for FR-INK-002. Gamma is clamped to 0.3–3.0.
class PressureCurve {
  PressureCurve({double gamma = 1.0})
    : gamma = (gamma.isNaN ? 0.5 : gamma).clamp(0.3, 3.0),
      _constant = false;

  /// Constant-width mode, independent of digitizer pressure.
  const PressureCurve.linear() : gamma = 1.0, _constant = true;

  final double gamma;
  final bool _constant;

  double map(double pressure) =>
      _constant ? 0.5 : math.pow(_pressure(pressure), gamma).toDouble();
}

double _pressure(double value) => value.isNaN ? 0.5 : value.clamp(0.0, 1.0);

/// Maps pressure to radius in the same units as [baseWidth] (FR-INK-002).
/// Negative widths clamp to zero; NaN widths use 0.5.
double strokeRadius(double baseWidth, double mappedPressure) =>
    (baseWidth.isNaN ? 0.5 : math.max(0.0, baseWidth)) /
    2 *
    (0.35 + 1.3 * _pressure(mappedPressure));
