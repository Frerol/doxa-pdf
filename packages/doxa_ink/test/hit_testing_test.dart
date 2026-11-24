// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_ink/doxa_ink.dart';
import 'package:test/test.dart';

void main() {
  const line = [InkSample(-5, 0, 0, 0), InkSample(5, 0, 1, 100)];
  group('FR-INK-005', () {
    test('distances near endpoints and segment middle', () {
      expect(distanceToPolyline(0, 3, line), 3);
      expect(distanceToPolyline(8, 4, line), 5);
      expect(distanceToPolyline(-8, 4, line), 5);
      expect(distanceToPolyline(0, 0, []), double.infinity);
    });
    test('hit and miss including stroke radius', () {
      expect(hitsStroke(line, 0, 2, 1), isFalse);
      expect(hitsStroke(line, 0, 2, 1, strokeRadius: 1), isTrue);
      expect(hitsStroke(line, 6, 0, 1), isTrue);
      expect(hitsStroke(line, -6.1, 0, 1), isFalse);
      expect(hitsStroke([], 0, 0, 10), isFalse);
    });
    test('single-point and repeated-point strokes', () {
      expect(distanceToPolyline(-5, 2, [line.first]), 2);
      expect(hitsStroke([line.first], -5, 2, 2), isTrue);
      expect(hitsStroke([line.first], -5, 2, 1), isFalse);
      expect(distanceToPolyline(-5, 2, [line.first, line.first]), 2);
      expect(eraseSegment([line.first], 0, 0, 1), isEmpty);
    });
    test('middle erase splits even with no sample inside circle', () {
      final pieces = eraseSegment(line, 0, 0, 1);
      expect(pieces.length, 2);
      expect(pieces[0].map((p) => p.x), [-5, -1]);
      expect(pieces[1].map((p) => p.x), [1, 5]);
      expect(pieces[0].last.pressure, 0.4);
      expect(pieces[0].last.timeUs, 40);
      expect(pieces[1].first.pressure, 0.6);
      expect(pieces[1].first.timeUs, 60);
    });
    test('erase at either end', () {
      final left = eraseSegment(line, -5, 0, 2);
      expect(left.length, 1);
      expect(left.single.map((p) => p.x), [-3, 5]);
      final right = eraseSegment(line, 5, 0, 2);
      expect(right.single.map((p) => p.x), [-5, 3]);
    });
    test('erase everything and empty input', () {
      expect(eraseSegment(line, 0, 0, 10), isEmpty);
      expect(eraseSegment([], 0, 0, 1), isEmpty);
    });
    test('miss and tangent preserve a continuous piece', () {
      expect(eraseSegment(line, 0, 2, 1), [line]);
      expect(eraseSegment(line, 0, 1, 1), [line]);
      expect(eraseSegment(line, 0, 0, 0), [line]);
    });
    test('diagonal crossings lie on circle and multiple passes keep order', () {
      const diagonal = [
        InkSample(-3, -3, 0, 0),
        InkSample(3, 3, 1, 60),
        InkSample(-3, -3, 0, 120),
      ];
      final pieces = eraseSegment(diagonal, 0, 0, 1);
      expect(pieces.length, 3);
      for (final p in [
        pieces[0].last,
        pieces[1].first,
        pieces[1].last,
        pieces[2].first,
      ]) {
        expect(p.x * p.x + p.y * p.y, closeTo(1, 1e-12));
      }
      expect(pieces[1].any((p) => identical(p, diagonal[1])), isTrue);
    });
    test(
      'boundary vertices join correctly and duplicate points remain finite',
      () {
        const points = [
          InkSample(-2, 0, 0, 0),
          InkSample(-1, 0, 0, 1),
          InkSample(0, 0, 0, 2),
          InkSample(1, 0, 0, 3),
          InkSample(2, 0, 0, 4),
        ];
        final pieces = eraseSegment(points, 0, 0, 1);
        expect(pieces.length, 2);
        expect(pieces.first, points.take(2));
        expect(pieces.last, points.skip(3));
        expect(
          eraseSegment([line.first, line.first, line.last], 0, 0, 1).length,
          2,
        );
      },
    );
  });
}
