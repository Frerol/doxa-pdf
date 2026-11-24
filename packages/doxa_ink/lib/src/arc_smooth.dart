// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'ink_sample.dart';

/// Optional arc-length smoothing, ported from Spike B (ADR-0006).
/// Resamples at radius/4, then applies an endpoint-shrinking triangular window.
/// As in the prototype, interpolated samples carry the segment end timestamp.
List<InkSample> arcSmooth(List<InkSample> raw, double radius) {
  if (raw.length < 3 || radius <= 0 || !radius.isFinite) return [...raw];
  final h = radius / 4;
  if (h == 0) return [...raw];
  final res = <InkSample>[raw.first];
  var dist = 0.0;
  for (var i = 1; i < raw.length; i++) {
    final a = raw[i - 1], b = raw[i];
    final dx = b.x - a.x, dy = b.y - a.y;
    final seg = math.sqrt(dx * dx + dy * dy);
    if (seg == 0) continue;
    var t = h - dist;
    while (t <= seg) {
      final f = t / seg;
      res.add(
        InkSample(
          a.x + dx * f,
          a.y + dy * f,
          a.pressure + (b.pressure - a.pressure) * f,
          b.timeUs,
        ),
      );
      t += h;
    }
    dist = seg - (t - h);
  }
  res.add(raw.last);
  final out = <InkSample>[];
  for (var i = 0; i < res.length; i++) {
    final w = math.min(4, math.min(i, res.length - 1 - i));
    var sx = 0.0, sy = 0.0, sp = 0.0, sw = 0.0;
    for (var j = -w; j <= w; j++) {
      final wt = (w + 1 - j.abs()).toDouble();
      final q = res[i + j];
      sx += q.x * wt;
      sy += q.y * wt;
      sp += q.pressure * wt;
      sw += wt;
    }
    out.add(InkSample(sx / sw, sy / sw, sp / sw, res[i].timeUs));
  }
  return out;
}
