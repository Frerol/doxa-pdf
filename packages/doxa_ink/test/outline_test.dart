// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_ink/doxa_ink.dart';
import 'package:test/test.dart';

double _distanceToSegment(PdfPoint p, PdfPoint a, PdfPoint b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)).clamp(
    0.0,
    1.0,
  );
  return math.sqrt(
    math.pow(p.x - (a.x + t * dx), 2) + math.pow(p.y - (a.y + t * dy), 2),
  );
}

void main() {
  group('stroke widths (FR-INK-002, FR-INK-004)', () {
    final stroke = InkStroke(
      const [PdfPoint(0, 0), PdfPoint(1, 0), PdfPoint(2, 0)],
      pressures: const [0, 0.5, 1],
    );

    test('the pen follows pressure, never below the minimum share', () {
      expect(strokeWidths(stroke, 4, InkTool.pen), [
        4 * minPressureWidth,
        2,
        4,
      ]);
    });

    test('the highlighter and strokes without pressure keep one width', () {
      expect(strokeWidths(stroke, 4, InkTool.highlighter), [4, 4, 4]);
      expect(strokeWidths(InkStroke(stroke.points), 4, InkTool.pen), [4, 4, 4]);
    });
  });

  group('stroke outline', () {
    const line = [PdfPoint(0, 0), PdfPoint(50, 0), PdfPoint(100, 30)];

    test('every outline point lies at half the width from the centreline', () {
      final outline = strokeOutline(line, const [6, 6, 6]);
      for (final p in outline) {
        final d = math.min(
          _distanceToSegment(p, line[0], line[1]),
          _distanceToSegment(p, line[1], line[2]),
        );
        // Joins on the corner sit a little closer; never farther.
        expect(d, lessThanOrEqualTo(3 + 1e-9));
        expect(d, greaterThan(2));
      }
    });

    test('round caps reach past the ends; flat caps do not', () {
      double reach(List<PdfPoint> o) => o.map((p) => p.x).reduce(math.min);
      expect(reach(strokeOutline(line, const [6, 6, 6])), closeTo(-3, 0.1));
      expect(
        reach(strokeOutline(line, const [6, 6, 6], roundCaps: false)),
        closeTo(0, 1e-9),
      );
    });

    test('a dot is a circle or a square; repeated points are one point', () {
      const dot = [PdfPoint(10, 10), PdfPoint(10, 10)];
      final circle = strokeOutline(dot, const [2, 4]);
      for (final p in circle) {
        expect(
          math.sqrt(math.pow(p.x - 10, 2) + math.pow(p.y - 10, 2)),
          closeTo(2, 1e-9),
        );
      }
      expect(strokeOutline(dot, const [4, 4], roundCaps: false), hasLength(4));
    });
  });
}
