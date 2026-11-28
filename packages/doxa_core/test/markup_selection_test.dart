// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_core/doxa_core.dart';
import 'package:test/test.dart';

MarkupTextRange page(List<(String, double, double)> lines) {
  final text = StringBuffer();
  final boxes = <double>[];
  final units = <int>[];
  for (final (line, left, baseline) in lines) {
    var x = left;
    for (final rune in line.runes) {
      final glyph = String.fromCharCode(rune);
      text.write(glyph);
      units.addAll(List.filled(glyph.length, boxes.length ~/ 4));
      if (glyph == '\r' || glyph == '\n' || glyph == ' ') {
        boxes.addAll([0, 0, 0, 0]);
      } else {
        boxes.addAll([x, baseline, x + 4, baseline + 8]);
      }
      x += 5;
    }
  }
  return (
    pageIndex: 0,
    text: text.toString(),
    charIndexOfUnit: units,
    charBoxes: boxes,
    charAngles: null,
    start: 0,
    end: boxes.length ~/ 4,
  );
}

void main() {
  test('FR-TEXT-005 orders interleaved fragments down columns', () {
    final selected = buildMarkupSelection([
      page([
        ('Left top', 0, 40),
        ('Right top\n', 100, 40),
        ('Left bottom\n', 0, 24),
        ('Right bottom', 100, 24),
      ]),
    ]).single;
    expect(selected.text, 'Left top\nLeft bottom\nRight top\nRight bottom');
    expect(selected.quads, hasLength(4));
    expect(
      selected.quads[1].boundingRect.right,
      lessThan(selected.quads[2].boundingRect.left),
    );
  });

  test('FR-MARK-010 joins wrapped words and respects UTF-16 mapping', () {
    final whole = page([
      ('X🙂 inter-\r\n', 0, 40),
      ('national co-op\r\n', 0, 24),
      ('nextY', 0, 8),
    ]);
    final selected = buildMarkupSelection([
      (
        pageIndex: whole.pageIndex,
        text: whole.text,
        charIndexOfUnit: whole.charIndexOfUnit,
        charBoxes: whole.charBoxes,
        charAngles: whole.charAngles,
        start: 1,
        end: whole.end - 1,
      ),
    ]).single;
    expect(selected.text, '🙂 international co-op\nnext');
    expect(selected.quads, hasLength(3));
    expect(selected.quads.first.boundingRect.left, closeTo(5, 0.5));
  });
}
