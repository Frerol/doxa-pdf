// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_ink/doxa_ink.dart';
import 'package:test/test.dart';

List<PdfRect> _line(double bottom) => [
  for (var i = 0; i < 10; i++)
    PdfRect(10 + i * 6.0, bottom, 15 + i * 6.0, bottom + 8),
];

void main() {
  group('FR-MARK-013 text snapping', () {
    final firstLine = _line(30);
    final secondLine = _line(18);
    final boxes = <PdfRect?>[...firstLine, null, ...secondLine];

    test('a sparse stroke across a line selects all its chars', () {
      final stroke = InkStroke(const [PdfPoint(10, 34), PdfPoint(69, 34)]);
      expect(snapStrokeToText(stroke, boxes), (start: 0, endExclusive: 10));
    });

    test('a backwards stroke selects just the touched chars', () {
      final stroke = InkStroke(const [PdfPoint(35, 34), PdfPoint(23, 34)]);
      expect(snapStrokeToText(stroke, boxes), (start: 2, endExclusive: 5));
    });

    test('two lines select both and preserve the intervening char index', () {
      const points = [
        PdfPoint(10, 34),
        PdfPoint(69, 34),
        PdfPoint(69, 22),
        PdfPoint(10, 22),
      ];
      for (final path in [points, points.reversed.toList()]) {
        expect(snapStrokeToText(InkStroke(path), boxes), (
          start: 0,
          endExclusive: boxes.length,
        ));
      }
    });

    test('skipping a text line stays ink', () {
      final stroke = InkStroke(const [
        PdfPoint(10, 34),
        PdfPoint(69, 34),
        PdfPoint(69, 10),
        PdfPoint(10, 10),
      ]);
      expect(snapStrokeToText(stroke, [...boxes, null, ..._line(6)]), isNull);
    });

    test('a loop around a word stays ink even inside the text band', () {
      final stroke = InkStroke(const [
        PdfPoint(10, 34),
        PdfPoint(14, 37),
        PdfPoint(60, 37),
        PdfPoint(65, 34),
        PdfPoint(60, 31),
        PdfPoint(14, 31),
        PdfPoint(10, 34),
      ]);
      expect(snapStrokeToText(stroke, boxes), isNull);
    });

    test('a margin stroke stays ink', () {
      final stroke = InkStroke(const [PdfPoint(10, 48), PdfPoint(69, 48)]);
      expect(snapStrokeToText(stroke, boxes), isNull);
    });

    test('dense samples over text cannot outweigh a long off-text segment', () {
      final stroke = InkStroke([
        for (var i = 10; i <= 69; i++) PdfPoint(i.toDouble(), 34),
        const PdfPoint(169, 34),
      ]);
      expect(snapStrokeToText(stroke, boxes), isNull);
    });

    test('a visible stroke on a rotated and cropped page selects the line', () {
      final transform = PageTransform(
        cropBox: const PdfRect(5, 5, 80, 100),
        rotation: 90,
        scale: 2,
      );
      // The line runs vertically on screen after rotating the page.
      final stroke = InkStroke([
        transform.toUser(58, 10),
        transform.toUser(58, 128),
      ]);
      expect(snapStrokeToText(stroke, boxes), (start: 0, endExclusive: 10));
    });
  });
}
