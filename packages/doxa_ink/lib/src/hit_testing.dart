// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'ink_sample.dart';

/// Distance to the nearest segment, or infinity for an empty polyline.
double distanceToPolyline(double x, double y, List<InkSample> samples) {
  var best = double.infinity;
  for (var i = 0; i < samples.length; i++) {
    final a = samples[i == 0 ? 0 : i - 1], b = samples[i];
    final dx = b.x - a.x, dy = b.y - a.y;
    final lengthSquared = dx * dx + dy * dy;
    final t = lengthSquared == 0
        ? 0.0
        : (((x - a.x) * dx + (y - a.y) * dy) / lengthSquared).clamp(0.0, 1.0);
    final ex = x - a.x - t * dx, ey = y - a.y - t * dy;
    best = math.min(best, math.sqrt(ex * ex + ey * ey));
  }
  return best;
}

/// Whole-stroke eraser test, including the stroke's own radius (FR-INK-005).
bool hitsStroke(
  List<InkSample> samples,
  double x,
  double y,
  double radius, {
  double strokeRadius = 0,
}) =>
    samples.isNotEmpty &&
    distanceToPolyline(x, y, samples) <=
        math.max(0.0, radius) + math.max(0.0, strokeRadius);

InkSample _interpolate(InkSample a, InkSample b, double t) {
  if (t == 0) return a;
  if (t == 1) return b;
  return InkSample(
    a.x + (b.x - a.x) * t,
    a.y + (b.y - a.y) * t,
    a.pressure + (b.pressure - a.pressure) * t,
    (a.timeUs + (b.timeUs - a.timeUs) * t).round(),
  );
}

/// Removes circle interiors, retaining exact boundary intersections (FR-INK-005).
/// Tangency does not split a stroke. Pieces with fewer than two samples drop.
/// Nonpositive radii leave strokes unchanged, subject to the piece length rule.
List<List<InkSample>> eraseSegment(
  List<InkSample> samples,
  double x,
  double y,
  double radius,
) {
  if (samples.length < 2) return [];
  if (radius <= 0) {
    return [
      [...samples],
    ];
  }
  final result = <List<InkSample>>[];
  var piece = <InkSample>[];
  void flush() {
    if (piece.length >= 2) result.add(piece);
    piece = <InkSample>[];
  }

  for (var i = 1; i < samples.length; i++) {
    final a = samples[i - 1], b = samples[i];
    final dx = b.x - a.x, dy = b.y - a.y;
    final fx = a.x - x, fy = a.y - y;
    final aa = dx * dx + dy * dy;
    final bb = 2 * (fx * dx + fy * dy);
    final cc = fx * fx + fy * fy - radius * radius;
    final cuts = <double>[0, 1];
    final discriminant = bb * bb - 4 * aa * cc;
    if (aa > 0 && discriminant > 0) {
      final root = math.sqrt(discriminant);
      for (final t in [(-bb - root) / (2 * aa), (-bb + root) / (2 * aa)]) {
        if (t > 0 && t < 1) cuts.add(t);
      }
      cuts.sort();
    }
    for (var j = 1; j < cuts.length; j++) {
      final start = cuts[j - 1], end = cuts[j];
      final mid = (start + end) / 2;
      final mx = fx + dx * mid, my = fy + dy * mid;
      if (mx * mx + my * my < radius * radius) {
        flush();
      } else {
        if (piece.isEmpty) piece.add(_interpolate(a, b, start));
        piece.add(_interpolate(a, b, end));
      }
    }
  }
  flush();
  return result;
}
