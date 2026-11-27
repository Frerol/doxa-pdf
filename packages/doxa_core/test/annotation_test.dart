// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:doxa_core/doxa_core.dart';
import 'package:test/test.dart';

void main() {
  group('ownership marker (ADR-0005 §5)', () {
    test('a new id is recognised, with the version key', () {
      final id = DoxaMarker.newId();
      expect(id, startsWith('doxa:'));
      expect(DoxaMarker.isDoxaId(id), isTrue);
      expect(DoxaMarker.owns(nm: id, versionValue: DoxaMarker.version), isTrue);
      expect(DoxaMarker.newId(), isNot(id));
    });

    test('foreign ids and a missing version key are not Doxa\'s', () {
      final uuid = AnnotationId.generate();
      for (final nm in [
        null,
        uuid,
        'other:$uuid',
        'doxa:',
        'doxa:not-a-uuid',
        'DOXA:$uuid',
      ]) {
        expect(
          DoxaMarker.owns(nm: nm, versionValue: '1'),
          isFalse,
          reason: nm,
        );
      }
      // The prefix alone, which another app could copy, is not enough.
      for (final version in [null, '']) {
        expect(
          DoxaMarker.owns(nm: 'doxa:$uuid', versionValue: version),
          isFalse,
        );
      }
    });
  });

  group('text markup (FR-MARK-001)', () {
    test('its /Rect is the bounding box of its quads, rotated ones too', () {
      final line1 = PdfQuad.fromRect(const PdfRect(10, 100, 200, 112));
      // A quad of a line rotated 90 degrees.
      const rotated = PdfQuad(
        PdfPoint(300, 50),
        PdfPoint(300, 250),
        PdfPoint(312, 50),
        PdfPoint(312, 250),
      );
      final markup = TextMarkup(
        id: 'a',
        pageIndex: 0,
        kind: MarkupKind.highlight,
        quads: [line1, rotated],
      );
      expect(markup.rect, const PdfRect(10, 50, 312, 250));
      expect(markup.subtype, 'Highlight');
    });

    test('new quads give a new /Rect; other changes keep it', () {
      final markup = TextMarkup(
        id: 'a',
        pageIndex: 0,
        kind: MarkupKind.underline,
        quads: [PdfQuad.fromRect(const PdfRect(0, 0, 10, 10))],
        // A file's own /Rect, a little larger than the quads.
        rect: const PdfRect(-1, -1, 11, 11),
      );
      expect(markup.copyWith(color: 0xFF0000).rect, markup.rect);
      expect(
        markup
            .copyWith(quads: [PdfQuad.fromRect(const PdfRect(0, 0, 5, 5))])
            .rect,
        const PdfRect(0, 0, 5, 5),
      );
    });

    test('subtype names map both ways', () {
      for (final kind in MarkupKind.values) {
        expect(MarkupKind.fromSubtype(kind.subtype), kind);
      }
      expect(MarkupKind.fromSubtype('Ink'), isNull);
    });
  });

  group('ink (FR-INK-001)', () {
    test('its /Rect covers every point and half the width', () {
      final ink = InkAnnotation(
        id: 'i',
        pageIndex: 2,
        width: 4,
        strokes: [
          InkStroke(const [PdfPoint(10, 10), PdfPoint(20, 30)]),
          InkStroke(const [PdfPoint(50, 5)]),
        ],
      );
      expect(ink.rect, const PdfRect(8, 3, 52, 32));
      expect(ink.copyWith(width: 10).rect, const PdfRect(5, 0, 55, 35));
    });

    test('equal values are equal, pressures included', () {
      InkAnnotation make(List<double>? pressures) => InkAnnotation(
        id: 'i',
        pageIndex: 0,
        width: 2,
        strokes: [
          InkStroke(const [
            PdfPoint(0, 0),
            PdfPoint(1, 1),
          ], pressures: pressures),
        ],
      );
      expect(make([0.2, 0.4]), make([0.2, 0.4]));
      expect(make([0.2, 0.4]).hashCode, make([0.2, 0.4]).hashCode);
      expect(make([0.2, 0.4]), isNot(make([0.2, 0.5])));
      expect(make(null), isNot(make([0.2, 0.4])));
    });
  });

  group('/DoxaPressure encoding', () {
    test('round trips within half a quantisation step', () {
      final strokes = [
        [0.0, 0.13, 0.5, 0.77, 1.0],
        <double>[],
        [0.333],
      ];
      final decoded = PressureCodec.decode(PressureCodec.encode(strokes))!;
      expect(decoded, hasLength(strokes.length));
      const halfStep = 0.5 / (PressureCodec.levels - 1);
      for (var s = 0; s < strokes.length; s++) {
        expect(decoded[s], hasLength(strokes[s].length));
        for (var i = 0; i < strokes[s].length; i++) {
          expect(decoded[s][i], closeTo(strokes[s][i], halfStep + 1e-9));
        }
      }
    });

    test('out-of-range pressures are clamped, foreign text is refused', () {
      expect(
        PressureCodec.decode(
          PressureCodec.encode([
            [-1, 2],
          ]),
        ),
        [
          [0.0, 1.0],
        ],
      );
      expect(PressureCodec.decode('AB*C'), isNull);
      // One character per pressure keeps long strokes small.
      expect(PressureCodec.encode([List.filled(500, 0.5)]), hasLength(500));
    });
  });
}
