// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'package:doxa_core/doxa_core.dart';

/// The smallest share of the full width that a pen stroke keeps at the
/// lightest pressure, so a light touch still leaves a visible line.
const minPressureWidth = 0.1;

/// The width of [stroke] at each point (FR-INK-002).
///
/// `/DoxaPressure` holds the pressure after the user's sensitivity curve,
/// so the width is [width] times that pressure, kept above
/// [minPressureWidth]. The highlighter pen has a flat tip of constant width
/// (FR-INK-004), and so does a stroke without pressure.
List<double> strokeWidths(InkStroke stroke, double width, InkTool tool) {
  final pressures = stroke.pressures;
  if (tool == InkTool.highlighter || pressures == null) {
    return List.filled(stroke.points.length, width);
  }
  return [
    for (final p in pressures)
      width * math.max(p.clamp(0.0, 1.0), minPressureWidth),
  ];
}

/// The outline of a stroke as one closed polygon: the left side, the end
/// cap, the right side backwards and the start cap. With [roundCaps] the
/// ends are half circles (the pen); without, they are cut square (the
/// highlighter's flat tip). A single point gives a circle, or a square
/// without round caps.
List<PdfPoint> strokeOutline(
  List<PdfPoint> points,
  List<double> widths, {
  bool roundCaps = true,
  int capSegments = 8,
}) {
  assert(points.isNotEmpty && points.length == widths.length);
  // Repeated points have no direction; drop them, keeping the widest.
  final pts = <PdfPoint>[points.first];
  final ws = <double>[widths.first];
  for (var i = 1; i < points.length; i++) {
    final p = points[i];
    if (p.x == pts.last.x && p.y == pts.last.y) {
      ws.last = math.max(ws.last, widths[i]);
    } else {
      pts.add(p);
      ws.add(widths[i]);
    }
  }
  if (pts.length == 1) {
    final c = pts.single;
    final r = ws.single / 2;
    if (!roundCaps) {
      return [
        PdfPoint(c.x - r, c.y - r),
        PdfPoint(c.x + r, c.y - r),
        PdfPoint(c.x + r, c.y + r),
        PdfPoint(c.x - r, c.y + r),
      ];
    }
    final n = capSegments * 2;
    return [
      for (var i = 0; i < n; i++)
        PdfPoint(
          c.x + r * math.cos(2 * math.pi * i / n),
          c.y + r * math.sin(2 * math.pi * i / n),
        ),
    ];
  }

  final left = <PdfPoint>[], right = <PdfPoint>[];
  for (var i = 0; i < pts.length; i++) {
    final a = pts[math.max(i - 1, 0)];
    final b = pts[math.min(i + 1, pts.length - 1)];
    final dx = b.x - a.x, dy = b.y - a.y;
    final length = math.sqrt(dx * dx + dy * dy);
    final nx = -dy / length, ny = dx / length;
    final r = ws[i] / 2;
    left.add(PdfPoint(pts[i].x + nx * r, pts[i].y + ny * r));
    right.add(PdfPoint(pts[i].x - nx * r, pts[i].y - ny * r));
  }

  List<PdfPoint> cap(PdfPoint centre, PdfPoint from, double radius) {
    // Half a circle from [from] around [centre], turning clockwise.
    final start = math.atan2(from.y - centre.y, from.x - centre.x);
    return [
      for (var k = 1; k < capSegments; k++)
        PdfPoint(
          centre.x + radius * math.cos(start - math.pi * k / capSegments),
          centre.y + radius * math.sin(start - math.pi * k / capSegments),
        ),
    ];
  }

  return [
    ...left,
    if (roundCaps) ...cap(pts.last, left.last, ws.last / 2),
    ...right.reversed,
    if (roundCaps) ...cap(pts.first, right.first, ws.first / 2),
  ];
}
