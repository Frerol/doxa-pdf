// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:doxa_core/doxa_core.dart';
import 'package:test/test.dart';

void main() {
  const crop = PdfRect(10, 20, 110, 220);
  const corners = [
    PdfPoint(10, 220),
    PdfPoint(110, 220),
    PdfPoint(10, 20),
    PdfPoint(110, 20),
  ];
  const mappings = <int, List<(double, double)>>{
    0: [(0, 0), (200, 0), (0, 400), (200, 400)],
    90: [(400, 0), (400, 200), (0, 0), (0, 200)],
    180: [(200, 400), (0, 400), (200, 0), (0, 0)],
    270: [(0, 200), (0, 0), (400, 200), (400, 0)],
  };
  for (final rotation in mappings.keys) {
    test('T-04 known corners and view size at $rotation degrees', () {
      final transform = PageTransform(
        cropBox: crop,
        rotation: rotation,
        scale: 2,
      );
      for (var i = 0; i < corners.length; i++) {
        final expected = mappings[rotation]![i];
        expect(transform.toView(corners[i]), expected);
        expect(transform.toUser(expected.$1, expected.$2), corners[i]);
      }
      expect(
        transform.viewSize,
        rotation == 90 || rotation == 270 ? (400.0, 200.0) : (200.0, 400.0),
      );
    });
    test('T-04 fractional round trips at $rotation degrees', () {
      final transform = PageTransform(
        cropBox: crop,
        rotation: rotation,
        scale: 1.7,
      );
      for (final point in [
        ...corners,
        const PdfPoint(33.2, 82.7),
        const PdfPoint(-5, 240),
      ]) {
        final (x, y) = transform.toView(point);
        final result = transform.toUser(x, y);
        expect(result.x, closeTo(point.x, 1e-10));
        expect(result.y, closeTo(point.y, 1e-10));
      }
      final user = transform.toUser(12.3, 45.6);
      final view = transform.toView(user);
      expect(view.$1, closeTo(12.3, 1e-10));
      expect(view.$2, closeTo(45.6, 1e-10));
    });
  }
  test('T-04 invalid rotation and scale are rejected', () {
    expect(
      () => PageTransform(cropBox: crop, rotation: 45),
      throwsArgumentError,
    );
    for (final scale in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => PageTransform(cropBox: crop, scale: scale),
        throwsArgumentError,
      );
    }
    expect(
      () => PageTransform(cropBox: const PdfRect(0, 0, double.infinity, 1)),
      throwsArgumentError,
    );
  });
  test('T-04 reversed and degenerate crop boxes', () {
    final reversed = PageTransform(cropBox: const PdfRect(110, 220, 10, 20));
    expect(reversed.toView(const PdfPoint(10, 220)), (0.0, 0.0));
    final point = PageTransform(cropBox: const PdfRect(10, 20, 10, 20));
    expect(point.viewSize, (0.0, 0.0));
    expect(point.toUser(0, 0), const PdfPoint(10, 20));
  });
}
