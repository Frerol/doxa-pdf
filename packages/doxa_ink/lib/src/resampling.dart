// SPDX-License-Identifier: GPL-3.0-or-later

import 'ink_sample.dart';

/// Drops samples closer than [minStep] to the last retained sample.
/// Endpoints are always retained. Nonpositive steps return a copy.
List<InkSample> resampleByDistance(List<InkSample> samples, double minStep) {
  if (samples.length < 3 || minStep <= 0) return [...samples];
  final result = <InkSample>[samples.first];
  for (var i = 1; i < samples.length - 1; i++) {
    final dx = samples[i].x - result.last.x;
    final dy = samples[i].y - result.last.y;
    if (dx * dx + dy * dy >= minStep * minStep) result.add(samples[i]);
  }
  result.add(samples.last);
  return result;
}

/// Ramer–Douglas–Peucker simplification on positions, preserving kept samples.
/// Nonpositive tolerance returns a copy, including collinear samples.
List<InkSample> simplify(List<InkSample> samples, double tolerance) {
  if (samples.length < 3 || tolerance <= 0) return [...samples];
  final keep = <int>{0, samples.length - 1};
  final pending = <(int, int)>[(0, samples.length - 1)];
  while (pending.isNotEmpty) {
    final (start, end) = pending.removeLast();
    final a = samples[start], b = samples[end];
    final dx = b.x - a.x, dy = b.y - a.y;
    final lengthSquared = dx * dx + dy * dy;
    var maxDistance = tolerance * tolerance;
    var farthest = -1;
    for (var i = start + 1; i < end; i++) {
      final p = samples[i];
      final t = lengthSquared == 0
          ? 0.0
          : (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared).clamp(
              0.0,
              1.0,
            );
      final ex = p.x - a.x - t * dx, ey = p.y - a.y - t * dy;
      final distance = ex * ex + ey * ey;
      if (distance > maxDistance) {
        maxDistance = distance;
        farthest = i;
      }
    }
    if (farthest >= 0) {
      keep.add(farthest);
      pending.add((start, farthest));
      pending.add((farthest, end));
    }
  }
  return [for (final i in keep.toList()..sort()) samples[i]];
}
