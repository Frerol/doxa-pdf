// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:test/test.dart';

String corpus(String name) {
  for (final dir in ['test_corpus', '../../test_corpus']) {
    final file = File('$dir/$name');
    if (file.existsSync()) return file.absolute.path;
  }
  throw StateError('Missing test_corpus/$name');
}

const _doxaHighlight = 'doxa:0b3f6c1e-2a4d-4e8f-9a1b-3c5d7e9f1a2b';

final _when = DateTime.utc(2026, 11, 27, 12);

TextMarkup _markup(int page, {String? id, int color = 0x00FF00}) => TextMarkup(
  id: id ?? DoxaMarker.newId(),
  pageIndex: page,
  kind: MarkupKind.squiggly,
  quads: [
    PdfQuad.fromRect(const PdfRect(72, 678, 300, 694)),
    PdfQuad.fromRect(const PdfRect(72, 658, 250, 674)),
  ],
  text: 'The morning light',
  color: color,
  opacity: 0.6,
  author: 'Ana',
  contents: 'A note',
  modified: _when,
  byDoxa: true,
);

void main() {
  late PdfiumEngine engine;

  setUpAll(() async => engine = await PdfiumEngine.spawn());
  tearDownAll(() => engine.dispose());

  /// Opens a copy in memory: editing never touches the corpus file.
  Future<DocumentHandle> openCopy(String name) async {
    final bytes = File(corpus(name)).readAsBytesSync();
    final result = await engine.open(MemorySource(bytes));
    final handle = (result as DocumentOpened).handle;
    addTearDown(() => engine.close(handle));
    return handle;
  }

  Future<T> find<T extends Annotation>(
    DocumentHandle doc,
    int page,
    String id,
  ) async =>
      (await engine.annotations(doc, page)).singleWhere((a) => a.id == id) as T;

  Matcher fails(EngineErrorKind kind) =>
      throwsA(isA<PdfEngineException>().having((e) => e.kind, 'kind', kind));

  group('adding (FR-MARK-001, FR-MARK-010, FR-INK-001)', () {
    test('markup reads back with every value, on normal, rotated and cropped '
        'pages', () async {
      final doc = await openCopy('annotations.pdf');
      for (final page in [0, 1, 2]) {
        final added = _markup(page);
        await engine.addAnnotations(doc, [added]);
        final read = await find<TextMarkup>(doc, page, added.id);
        expect(read.byDoxa, isTrue);
        expect(read.kind, MarkupKind.squiggly);
        expect(read.quads, added.quads);
        expect(read.rect, added.rect);
        expect(read.color, 0x00FF00);
        // PDFium keeps /CA as an 8-bit alpha.
        expect(read.opacity, closeTo(0.6, 1 / 255));
        expect(read.text, 'The morning light');
        expect(read.contents, 'A note');
        expect(read.author, 'Ana');
        expect(read.modified, _when);
        expect(read.flags, Annotation.printFlag);
      }
    });

    test('ink reads back with its strokes, width, tool and pressure, and '
        'carries an appearance in its colour', () async {
      final doc = await openCopy('annotations.pdf');
      final pen = InkAnnotation(
        id: DoxaMarker.newId(),
        pageIndex: 0,
        width: 3,
        color: 0x1565C0,
        strokes: [
          InkStroke(
            const [PdfPoint(100, 200), PdfPoint(150, 230), PdfPoint(200, 210)],
            pressures: const [0.2, 0.9, 0.5],
          ),
          InkStroke(const [PdfPoint(120, 180)], pressures: const [1]),
        ],
        modified: _when,
        byDoxa: true,
      );
      final marker = InkAnnotation(
        id: DoxaMarker.newId(),
        pageIndex: 0,
        width: 12,
        tool: InkTool.highlighter,
        color: 0xFFEB00,
        opacity: 0.5,
        strokes: [
          InkStroke(const [PdfPoint(80, 100), PdfPoint(300, 100)]),
        ],
        byDoxa: true,
      );
      await engine.addAnnotations(doc, [pen, marker]);

      final readPen = await find<InkAnnotation>(doc, 0, pen.id);
      expect(readPen.byDoxa, isTrue);
      expect(readPen.tool, InkTool.pen);
      expect(readPen.width, 3);
      expect(readPen.strokes.map((s) => s.points), [
        for (final s in pen.strokes) s.points,
      ]);
      for (final (i, stroke) in readPen.strokes.indexed) {
        final wanted = pen.strokes[i].pressures!;
        for (final (j, p) in stroke.pressures!.indexed) {
          expect(p, closeTo(wanted[j], 0.5 / (PressureCodec.levels - 1)));
        }
      }
      // PDFium reports no /C once an appearance exists, so this colour
      // comes from the appearance Doxa built.
      expect(readPen.color, 0x1565C0);

      final readMarker = await find<InkAnnotation>(doc, 0, marker.id);
      expect(readMarker.tool, InkTool.highlighter);
      expect(readMarker.color, 0xFFEB00);
      expect(readMarker.strokes.single.pressures, isNull);
    });

    test('only Doxa ids, only once, and only markup or ink', () async {
      final doc = await openCopy('annotations.pdf');
      await expectLater(
        engine.addAnnotations(doc, [_markup(0, id: AnnotationId.generate())]),
        fails(EngineErrorKind.unsupportedEdit),
      );
      await expectLater(
        engine.addAnnotations(doc, [_markup(0, id: _doxaHighlight)]),
        fails(EngineErrorKind.unsupportedEdit),
      );
      await expectLater(
        engine.addAnnotations(doc, [
          OtherAnnotation(
            id: DoxaMarker.newId(),
            pageIndex: 0,
            rect: const PdfRect(0, 0, 10, 10),
            subtype: 'Square',
          ),
        ]),
        fails(EngineErrorKind.unsupportedEdit),
      );
      await expectLater(
        engine.addAnnotations(doc, [_markup(9)]),
        fails(EngineErrorKind.invalidPage),
      );
    });
  });

  group('changing (FR-ANNO-002)', () {
    test('Doxa\'s markup takes any change, its id stays', () async {
      final doc = await openCopy('annotations.pdf');
      final current = await find<TextMarkup>(doc, 0, _doxaHighlight);
      final moved = current.copyWith(
        kind: MarkupKind.underline,
        quads: [PdfQuad.fromRect(const PdfRect(72, 638, 200, 654))],
        color: 0xFF0000,
        contents: 'Changed',
      );
      final stored = await engine.updateAnnotation(doc, moved);
      expect(stored, isA<TextMarkup>());
      expect(stored.id, _doxaHighlight);
      final read = await find<TextMarkup>(doc, 0, _doxaHighlight);
      expect(read.kind, MarkupKind.underline);
      expect(read.quads, moved.quads);
      expect(read.color, 0xFF0000);
      expect(read.contents, 'Changed');
      expect(read.text, 'A field notebook');
    });

    test('another app\'s markup keeps its geometry; a markup without /NM '
        'gets one', () async {
      final doc = await openCopy('annotations.pdf');
      final underline = (await engine.annotations(doc, 0))
          .whereType<TextMarkup>()
          .singleWhere((m) => m.kind == MarkupKind.underline);
      final stored = await engine.updateAnnotation(
        doc,
        underline.copyWith(color: 0xFF00FF, contents: 'Mine now'),
      );
      expect(AnnotationId.isValid(stored.id), isTrue);
      expect(stored.byDoxa, isFalse);
      final read = await find<TextMarkup>(doc, 0, stored.id);
      expect(read.color, 0xFF00FF);
      expect(read.contents, 'Mine now');
      expect(read.quads, underline.quads);

      await expectLater(
        engine.updateAnnotation(
          doc,
          read.copyWith(quads: [PdfQuad.fromRect(const PdfRect(0, 0, 9, 9))]),
        ),
        fails(EngineErrorKind.unsupportedEdit),
      );
    });

    test(
      'another app\'s highlight drops its appearance to change colour',
      () async {
        final doc = await openCopy('annotated-acrobat.pdf');
        final highlight =
            (await engine.annotations(doc, 0)).single as TextMarkup;
        expect(highlight.color, 0x9643FC);
        await engine.updateAnnotation(doc, highlight.copyWith(color: 0x00FF00));
        final read = (await engine.annotations(doc, 0)).single as TextMarkup;
        expect(read.color, 0x00FF00);
        expect(read.quads, highlight.quads);
        expect(read.id, highlight.id);
      },
    );

    test('another app\'s appearance that sets the colour is refused', () async {
      // pdf.js's free text has an appearance; rebuilding it is not Doxa's
      // to do.
      final doc = await openCopy('annotated-pdfjs.pdf');
      final note = (await engine.annotations(doc, 0)).single;
      await expectLater(
        engine.updateAnnotation(
          doc,
          (note as OtherAnnotation).copyWith(color: 0xFF0000),
        ),
        fails(EngineErrorKind.unsupportedEdit),
      );
      // Its note can still change.
      final stored = await engine.updateAnnotation(
        doc,
        note.copyWith(contents: 'Seen'),
      );
      expect(stored.contents, 'Seen');
    });

    test('an unknown id is an error', () async {
      final doc = await openCopy('annotations.pdf');
      await expectLater(
        engine.updateAnnotation(doc, _markup(0)),
        fails(EngineErrorKind.unknownAnnotation),
      );
    });
  });

  group('deleting', () {
    test('nothing is deleted when one id is unknown', () async {
      final doc = await openCopy('annotations.pdf');
      final before = await engine.annotations(doc, 0);
      await expectLater(
        engine.deleteAnnotations(doc, 0, ['square-1', 'no-such-id']),
        fails(EngineErrorKind.unknownAnnotation),
      );
      expect(await engine.annotations(doc, 0), before);
    });
  });
}
