// SPDX-License-Identifier: GPL-3.0-or-later

/// Ink pipeline of Doxa PDF: stroke model, optional arc-length smoothing,
/// pressure-to-width mapping, variable-width outlines, hit testing and
/// erasing. Pure Dart. See docs/plan/03-architecture.md §6.
library;

export 'src/pressure_curve.dart';

/// Name of this package, used by smoke tests until real APIs land.
const String packageName = 'doxa_ink';
