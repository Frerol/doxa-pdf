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

void main() {
  late PdfiumEngine engine;

  setUpAll(() async => engine = await PdfiumEngine.spawn());
  tearDownAll(() => engine.dispose());

  Future<DocumentHandle> openFile(String name) async {
    final result = await engine.open(FileSource(corpus(name)));
    final handle = (result as DocumentOpened).handle;
    addTearDown(() => engine.close(handle));
    return handle;
  }

  T only<T extends Annotation>(List<Annotation> list, String id) =>
      list.singleWhere((a) => a.id == id) as T;

  group('reading annotations (FR-ANNO-002)', () {
    test(
      'Doxa\'s markup comes back with every value it was written with',
      () async {
        final doc = await openFile('annotations.pdf');
        final page = await engine.annotations(doc, 0);
        final markup = only<TextMarkup>(
          page,
          'doxa:0b3f6c1e-2a4d-4e8f-9a1b-3c5d7e9f1a2b',
        );
        expect(markup.byDoxa, isTrue);
        expect(markup.kind, MarkupKind.highlight);
        expect(markup.quads, [
          const PdfQuad(
            PdfPoint(72, 714),
            PdfPoint(328, 714),
            PdfPoint(72, 698),
            PdfPoint(328, 698),
          ),
        ]);
        expect(markup.rect, const PdfRect(70, 696, 330, 716));
        expect(markup.color, 0xFFFF00);
        expect(markup.opacity, closeTo(0.4, 1e-6));
        expect(markup.text, 'A field notebook');
        expect(markup.contents, 'Check the date');
        expect(markup.author, 'Ana');
        expect(markup.modified, DateTime.utc(2026, 11, 27, 10, 30));
        expect(markup.flags, Annotation.printFlag);
      },
    );

    test('foreign markup without /NM gets an id, and is not Doxa\'s', () async {
      final doc = await openFile('annotations.pdf');
      final page = await engine.annotations(doc, 0);
      final underline = page.whereType<TextMarkup>().singleWhere(
        (m) => m.kind == MarkupKind.underline,
      );
      expect(underline.byDoxa, isFalse);
      expect(underline.id, isNotEmpty);
      expect(underline.quads, hasLength(2));
      expect(underline.color, 0x0000FF);
      expect(underline.text, isNull);
      // The id is the same on the next read, so commands can target it.
      final again = await engine.annotations(doc, 0);
      expect(
        again.whereType<TextMarkup>().map((m) => m.id),
        contains(underline.id),
      );
    });

    test('ink comes back with its paths, width, tool and pressure', () async {
      final doc = await openFile('annotations.pdf');
      final page = await engine.annotations(doc, 0);

      final foreign = only<InkAnnotation>(page, 'other-app-ink');
      expect(foreign.byDoxa, isFalse);
      expect(foreign.strokes.map((s) => s.points), [
        const [PdfPoint(100, 400), PdfPoint(200, 500), PdfPoint(300, 450)],
        const [PdfPoint(100, 450), PdfPoint(150, 460)],
      ]);
      expect(foreign.width, 3);
      expect(foreign.tool, InkTool.pen);
      expect(foreign.strokes.first.pressures, isNull);

      final own = only<InkAnnotation>(
        page,
        'doxa:5e7a9c1b-3d5f-4a7c-8e9a-1b3c5d7e9fa0',
      );
      expect(own.byDoxa, isTrue);
      expect(own.tool, InkTool.highlighter);
      expect(own.width, 8);
      expect(own.opacity, closeTo(0.5, 1e-6));
      expect(own.strokes.single.pressures, [0, 32 / 63, 0]);
    });

    test('popups and links are left out; other subtypes and broken markup '
        'are kept as what they are', () async {
      final doc = await openFile('annotations.pdf');
      final page = await engine.annotations(doc, 0);
      expect(page.map((a) => a.subtype), [
        'Highlight',
        'Underline',
        'Ink',
        'Ink',
        'Square',
        'Highlight',
      ]);
      expect(only<OtherAnnotation>(page, 'square-1').color, 0x000000);
      // A highlight whose /QuadPoints Doxa cannot use.
      expect(page.last, isA<OtherAnnotation>());
      expect(page.last.id, 'broken-quads');
    });

    test('quads stay in PDF user space on rotated and cropped pages', () async {
      final doc = await openFile('annotations.pdf');
      const quad = PdfQuad(
        PdfPoint(72, 714),
        PdfPoint(328, 714),
        PdfPoint(72, 698),
        PdfPoint(328, 698),
      );
      for (final (page, id) in [(1, 'rotated'), (2, 'cropped')]) {
        final markup = only<TextMarkup>(
          await engine.annotations(doc, page),
          id,
        );
        expect(markup.pageIndex, page);
        expect(markup.quads, [quad], reason: id);
      }
    });

    test(
      'the colour of an annotation with an appearance comes from it',
      () async {
        // Acrobat's highlight has an appearance stream, so PDFium does not
        // report its /C.
        final doc = await openFile('annotated-acrobat.pdf');
        final highlight = (await engine.annotations(doc, 0)).single;
        expect(highlight, isA<TextMarkup>());
        expect(highlight.byDoxa, isFalse);
        expect(highlight.color, 0x9643FC);
      },
    );

    test('reading changes nothing in the file', () async {
      final file = File(corpus('annotations.pdf'));
      final before = file.readAsBytesSync();
      final doc = await openFile('annotations.pdf');
      for (var page = 0; page < 3; page++) {
        await engine.annotations(doc, page);
      }
      await engine.close(doc);
      expect(file.readAsBytesSync(), before);
    });

    test(
      'a bad page index is an error, and the engine keeps serving',
      () async {
        final doc = await openFile('annotations.pdf');
        await expectLater(
          engine.annotations(doc, 3),
          throwsA(isA<PdfEngineException>()),
        );
        expect(await engine.annotations(doc, 1), hasLength(1));
      },
    );
  });
}
