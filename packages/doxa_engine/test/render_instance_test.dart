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

/// The RGB of PDF point ([x], [y]) on page 0 of `annotations.pdf`, rendered
/// at scale 1 (612 × 792, no rotation).
typedef Pixel = ({int r, int g, int b});

void main() {
  late PdfiumEngine engine;

  setUpAll(() async => engine = await PdfiumEngine.spawn());
  tearDownAll(() => engine.dispose());

  Future<DocumentHandle> openCopy() async {
    final bytes = File(corpus('annotations.pdf')).readAsBytesSync();
    final result = await engine.open(MemorySource(bytes));
    final handle = (result as DocumentOpened).handle;
    addTearDown(() => engine.close(handle));
    return handle;
  }

  Future<Pixel> pixelAt(DocumentHandle doc, double x, double y) async {
    final bitmap = await engine.render(
      RenderRequest(
        document: doc,
        pageIndex: 0,
        scale: 1,
        x: 0,
        y: 0,
        width: 612,
        height: 792,
        priority: RenderPriority.visibleTile,
        generation: 0,
      ),
    ) as RenderedBitmap;
    final i = ((792 - y).round() * bitmap.width + x.round()) * 4;
    final p = bitmap.pixels;
    return (r: p[i], g: p[i + 1], b: p[i + 2]);
  }

  bool isWhite(Pixel p) => p.r > 240 && p.g > 240 && p.b > 240;

  // Points on the fixture's annotations (tools/generate_corpus.py).
  // Doxa's highlighter ink runs from (100, 300) to (200, 310); another
  // app's red ink, 3 pt wide, from (100, 400) to (200, 500).
  const doxaInk = (x: 150.0, y: 305.0);
  const foreignInk = (x: 150.0, y: 450.0);

  group('render instance (ADR-0005 §3)', () {
    test('tiles leave out Doxa\'s annotations and keep other apps\'', () async {
      final doc = await openCopy();
      expect(isWhite(await pixelAt(doc, doxaInk.x, doxaInk.y)), isTrue);
      final red = await pixelAt(doc, foreignInk.x, foreignInk.y);
      expect(red.r, greaterThan(200));
      expect(red.g, lessThan(80));
      // Hidden in memory only: the annotation keeps its flags.
      final ink = (await engine.annotations(
        doc,
        0,
      )).singleWhere((a) => a.byDoxa && a is InkAnnotation);
      expect(ink.isHidden, isFalse);
    });

    test('a change to another app\'s annotation shows in tiles', () async {
      final doc = await openCopy();
      // Render first, so PDFium has built the ink's appearance.
      await pixelAt(doc, foreignInk.x, foreignInk.y);
      final foreign = (await engine.annotations(
        doc,
        0,
      )).singleWhere((a) => a.id == 'other-app-ink') as InkAnnotation;
      await engine.updateAnnotation(doc, foreign.copyWith(color: 0x0000FF));
      final blue = await pixelAt(doc, foreignInk.x, foreignInk.y);
      expect(blue.b, greaterThan(200));
      expect(blue.r, lessThan(80));

      await engine.deleteAnnotations(doc, 0, ['other-app-ink']);
      expect(isWhite(await pixelAt(doc, foreignInk.x, foreignInk.y)), isTrue);
    });

    test(
      'an annotation without /NM is followed after its first edit',
      () async {
        // The foreign underline has no /NM: its first edit gives it one in
        // the editing instance, and the render instance must follow it.
        final doc = await openCopy();
        final underline = (await engine.annotations(
          doc,
          0,
        )).singleWhere((a) => a is TextMarkup && !a.byDoxa) as TextMarkup;
        // The underline of the first quad, at y = 678.
        await pixelAt(doc, 300, 679);
        final first = await engine.updateAnnotation(
          doc,
          underline.copyWith(color: 0xFF0000),
        );
        expect(first.id, isNot(underline.id));
        final red = await pixelAt(doc, 300, 679);
        expect(red.r, greaterThan(red.b));
        await engine.updateAnnotation(
          doc,
          (first as TextMarkup).copyWith(color: 0x00FF00),
        );
        final green = await pixelAt(doc, 300, 679);
        expect(green.g, greaterThan(green.r));
      },
    );
  });
}
