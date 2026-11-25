// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:pdfium_ffi/testing.dart';
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

  Future<DocumentOpened> openFile(String name, {String? password}) async {
    final result = await engine.open(
      FileSource(corpus(name)),
      password: password,
    );
    expect(result, isA<DocumentOpened>(), reason: name);
    final opened = result as DocumentOpened;
    addTearDown(() => engine.close(opened.handle));
    return opened;
  }

  RenderRequest tile(
    DocumentHandle doc, {
    int page = 0,
    double scale = 1,
    int x = 0,
    int y = 0,
    int width = 64,
    int height = 64,
    RenderPriority priority = RenderPriority.visibleTile,
    int generation = 0,
  }) => RenderRequest(
    document: doc,
    pageIndex: page,
    scale: scale,
    x: x,
    y: y,
    width: width,
    height: height,
    priority: priority,
    generation: generation,
  );

  group('open', () {
    test('reads a memory document and its text', () async {
      final result = await engine.open(MemorySource(buildMinimalPdf()));
      final opened = result as DocumentOpened;
      addTearDown(() => engine.close(opened.handle));
      expect(opened.info.pageCount, 1);
      expect(opened.info.pageSize(0), (
        width: minimalPdfPageSize,
        height: minimalPdfPageSize,
      ));
      final text = await engine.pageText(opened.handle, 0);
      expect(text.text, minimalPdfText);
    });

    test('asks for a password, rejects a wrong one, accepts the right one '
        '(FR-FILE-003)', () async {
      final source = FileSource(corpus('encrypted.pdf'));
      expect(await engine.open(source), isA<PasswordRequired>());
      expect(await engine.open(source, password: 'nope'), isA<WrongPassword>());
      final opened = await openFile('encrypted.pdf', password: 'study');
      final text = await engine.pageText(opened.handle, 0);
      expect(text.text, contains('A field notebook'));
    });

    test('reports a missing file', () async {
      final result = await engine.open(const FileSource('/no/such/file.pdf'));
      expect(result, isA<OpenFailed>());
      expect((result as OpenFailed).reason, OpenFailure.file);
    });

    test('reports data that is not a PDF', () async {
      final result = await engine.open(
        MemorySource(Uint8List.fromList('hello, not a pdf'.codeUnits)),
      );
      expect((result as OpenFailed).reason, OpenFailure.format);
    });

    test('reads page sizes with rotation and crop box applied', () async {
      final rotated = await openFile('rotated-pages.pdf');
      expect(rotated.info.pageCount, 4);
      expect(rotated.info.pageSize(0), (width: 612.0, height: 792.0));
      expect(rotated.info.pageSize(1), (width: 792.0, height: 612.0));
      final cropped = await openFile('offset-cropbox.pdf');
      expect(cropped.info.pageSize(0), (width: 510.25, height: 666.25));
    });

    test('opens a 1,001-page document without loading its pages', () async {
      final watch = Stopwatch()..start();
      final opened = await openFile('many-pages.pdf');
      expect(opened.info.pageCount, 1001);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('document structure', () {
    test('reads page labels (FR-VIEW-014) and metadata', () async {
      final opened = await openFile('navigation.pdf');
      expect(opened.info.pageLabels, ['i', 'ii', '1', '2', '3', 'A-1']);
      expect(opened.info.hasPageLabels, isTrue);
      expect(opened.info.metadata.title, 'Navigation fixture');
      expect(opened.info.metadata.author, 'Doxa PDF');
      final plain = await openFile('two-column-article.pdf');
      expect(plain.info.pageLabels, [null]);
      expect(plain.info.hasPageLabels, isFalse);
    });

    test(
      'reads the outline with destinations and URIs (FR-VIEW-007)',
      () async {
        final opened = await openFile('navigation.pdf');
        final outline = await engine.outline(opened.handle);
        expect(outline.map((n) => n.title), [
          'Preface',
          'Chapter 1',
          'Project site',
        ]);
        expect(
          (outline[0].target! as GoToTarget).destination,
          const PdfDestination(0, x: 72, y: 720),
        );
        expect((outline[1].target! as GoToTarget).destination.pageIndex, 2);
        final section = outline[1].children.single;
        expect(section.title, 'Section 1.1');
        expect(
          (section.target! as GoToTarget).destination,
          const PdfDestination(3, x: 72, y: 400, zoom: 2),
        );
        expect(
          (outline[2].target! as UriTarget).uri,
          'https://example.org/doxa',
        );
        final plain = await openFile('two-column-article.pdf');
        expect(await engine.outline(plain.handle), isEmpty);
      },
    );

    test('reads internal, URI and unsupported links (FR-VIEW-010)', () async {
      final opened = await openFile('navigation.pdf');
      expect(await engine.pageLinks(opened.handle, 0), isEmpty);
      final links = await engine.pageLinks(opened.handle, 2);
      expect(links, hasLength(3));
      final goTo = links.singleWhere((l) => l.target is GoToTarget);
      expect(goTo.rect, const PdfRect(72, 600, 200, 620));
      expect((goTo.target as GoToTarget).destination.pageIndex, 5);
      final uri = links.singleWhere((l) => l.target is UriTarget);
      expect((uri.target as UriTarget).uri, 'https://example.org/');
      expect(links.map((l) => l.target), contains(isA<UnsupportedTarget>()));
    });

    test('reads crop box and rotation per page', () async {
      final rotated = await openFile('rotated-pages.pdf');
      final rotations = [
        for (var i = 0; i < 4; i++)
          (await engine.pageDetails(rotated.handle, i)).rotation,
      ];
      expect(rotations, [0, 90, 180, 270]);
      final cropped = await openFile('offset-cropbox.pdf');
      final details = await engine.pageDetails(cropped.handle, 0);
      expect(details.cropBox, const PdfRect(37.5, 62.25, 547.75, 728.5));
      expect(details.transform().viewSize, (510.25, 666.25));
    });

    test('throws typed errors for bad pages and handles', () async {
      final opened = await openFile('two-column-article.pdf');
      await expectLater(
        engine.pageText(opened.handle, 1),
        throwsA(
          isA<PdfEngineException>().having(
            (e) => e.kind,
            'kind',
            EngineErrorKind.invalidPage,
          ),
        ),
      );
      await expectLater(
        engine.outline(const DocumentHandle(9999)),
        throwsA(
          isA<PdfEngineException>().having(
            (e) => e.kind,
            'kind',
            EngineErrorKind.unknownDocument,
          ),
        ),
      );
    });
  });

  group('render', () {
    test('renders RGBA pixels of a page region', () async {
      final result = await engine.open(MemorySource(buildMinimalPdf()));
      final doc = (result as DocumentOpened).handle;
      addTearDown(() => engine.close(doc));
      // The black square covers PDF (60,20)–(140,100) on a 200 pt page:
      // view (60,100)–(140,180) from the top left.
      final whole = await engine.render(tile(doc, width: 200, height: 200));
      final bitmap = whole as RenderedBitmap;
      expect(bitmap.pixels.length, 200 * 200 * 4);
      List<int> pixel(RenderedBitmap b, int x, int y) =>
          b.pixels.sublist((y * b.width + x) * 4, (y * b.width + x) * 4 + 4);
      expect(pixel(bitmap, 100, 140).take(3), everyElement(lessThan(16)));
      expect(pixel(bitmap, 100, 140)[3], 255);
      expect(pixel(bitmap, 20, 20), [255, 255, 255, 255]);

      // A 2x tile whose origin is the square's top-left corner.
      final part = await engine.render(
        tile(doc, scale: 2, x: 120, y: 200, width: 32, height: 32),
      ) as RenderedBitmap;
      expect(pixel(part, 4, 4).take(3), everyElement(lessThan(16)));
      expect(part.width, 32);
    });

    test('renders rotated pages in display orientation', () async {
      final opened = await openFile('rotated-pages.pdf');
      final size = opened.info.pageSize(1);
      final bitmap = await engine.render(
        tile(
          opened.handle,
          page: 1,
          scale: 0.5,
          width: (size.width / 2).ceil(),
          height: (size.height / 2).ceil(),
        ),
      ) as RenderedBitmap;
      // Rotated 90°: the text runs top to bottom near x = 700 / 2.
      var minX = bitmap.width, maxX = 0;
      for (var y = 0; y < bitmap.height; y++) {
        for (var x = 0; x < bitmap.width; x++) {
          if (bitmap.pixels[(y * bitmap.width + x) * 4] < 128) {
            minX = min(minX, x);
            maxX = max(maxX, x);
          }
        }
      }
      expect(minX, inInclusiveRange(310, 330));
      expect(maxX, inInclusiveRange(345, 360));
    });

    test('skips renders of an older generation', () async {
      final opened = await openFile('many-pages.pdf');
      final doc = opened.handle;
      final futures = [
        for (var i = 0; i < 30; i++)
          engine.render(tile(doc, page: i, width: 512, height: 512)),
      ];
      engine.setGeneration(doc, 1);
      final fresh = engine.render(
        tile(doc, page: 500, generation: 1, width: 512, height: 512),
      );
      final results = await Future.wait(futures);
      expect(await fresh, isA<RenderedBitmap>());
      final skipped = results.whereType<RenderSkipped>().toList();
      // The generation arrives while the first renders are already queued:
      // at least most of them are dropped before PDFium sees them.
      expect(skipped.length, greaterThan(20));
      expect(skipped.map((s) => s.reason).toSet(), {SkipReason.stale});
    });

    test('cancels a render through its token', () async {
      final opened = await openFile('many-pages.pdf');
      final token = CancelToken()..cancel();
      final result = await engine.render(tile(opened.handle), cancel: token);
      expect((result as RenderSkipped).reason, SkipReason.cancelled);

      final busy = [
        for (var i = 0; i < 10; i++)
          engine.render(
            tile(opened.handle, page: i, width: 1024, height: 1024),
          ),
      ];
      final token2 = CancelToken();
      final cancelled = engine.render(
        tile(opened.handle, priority: RenderPriority.background),
        cancel: token2,
      );
      token2.cancel();
      expect(((await cancelled) as RenderSkipped).reason, SkipReason.cancelled);
      await Future.wait(busy);
    });

    test('closing a document skips its pending renders', () async {
      final result = await engine.open(FileSource(corpus('many-pages.pdf')));
      final doc = (result as DocumentOpened).handle;
      final pending = [
        for (var i = 0; i < 10; i++)
          engine.render(tile(doc, page: i, width: 1024, height: 1024)),
      ];
      await engine.close(doc);
      final results = await Future.wait(pending);
      expect(
        results.whereType<RenderSkipped>().map((r) => r.reason),
        everyElement(SkipReason.closed),
      );
      await expectLater(
        engine.render(tile(doc)),
        throwsA(isA<PdfEngineException>()),
      );
    });
  });

  group('text and search', () {
    test('gives each char a box in PDF user space', () async {
      final opened = await openFile('two-column-article.pdf');
      final text = await engine.pageText(opened.handle, 0);
      expect(text.text, contains('Notes from a river survey'));
      final first = text.text.indexOf('Notes');
      final box = text.charBox(text.charIndexOfUnit[first])!;
      expect(box.left, closeTo(60, 1.5));
      expect(box.bottom, closeTo(732, 4));
    });

    test('streams hits across pages (NFR-PERF-007)', () async {
      final opened = await openFile('many-pages.pdf');
      final watch = Stopwatch()..start();
      final stream = engine.search(opened.handle, const SearchQuery('river'));
      final first = await stream.first;
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(first.pageIndex, 0);
      expect(first.rects, hasLength(1));

      final all = await engine
          .search(opened.handle, const SearchQuery('RIVER'))
          .toList();
      expect(all, hasLength(1001));
      expect(all.last.pageIndex, 1000);
    });

    test('a cancelled search stops early', () async {
      final opened = await openFile('many-pages.pdf');
      final hits = await engine
          .search(opened.handle, const SearchQuery('valley'))
          .take(3)
          .toList();
      expect(hits.map((h) => h.pageIndex), [0, 1, 2]);
      // The engine still answers right after the cancellation.
      expect(await engine.pageText(opened.handle, 0), isA<PageText>());
    });

    test('search options are honoured (FR-TEXT-002)', () async {
      final opened = await openFile('two-column-article.pdf');
      Future<int> count(SearchQuery q) async =>
          (await engine.search(opened.handle, q).toList()).length;
      expect(await count(const SearchQuery('the')), 4);
      expect(await count(const SearchQuery('The', matchCase: true)), 1);
      expect(await count(const SearchQuery('the', wholeWord: true)), 4);
      expect(await count(const SearchQuery('river')), 2);
      expect(await count(const SearchQuery('two teams')), 1);
    });
  });

  group('hostile input (R3)', () {
    test('damaged copies never stop the engine', () async {
      final original = File(corpus('two-column-article.pdf')).readAsBytesSync();
      final random = Random(46);
      var opened = 0;
      for (var round = 0; round < 120; round++) {
        final bytes = Uint8List.fromList(original);
        if (round.isEven) {
          for (var i = 0; i < 12; i++) {
            bytes[random.nextInt(bytes.length)] = random.nextInt(256);
          }
        }
        final data = round.isEven
            ? bytes
            : bytes.sublist(0, random.nextInt(bytes.length));
        final result = await engine.open(MemorySource(data));
        if (result is! DocumentOpened) continue;
        opened++;
        final doc = result.handle;
        for (var page = 0; page < result.info.pageCount; page++) {
          await _ignoringDocumentErrors(() => engine.pageText(doc, page));
          await _ignoringDocumentErrors(() => engine.pageLinks(doc, page));
          await _ignoringDocumentErrors(() => engine.pageDetails(doc, page));
          await _ignoringDocumentErrors(
            () => engine.render(tile(doc, page: page)),
          );
        }
        await _ignoringDocumentErrors(() => engine.outline(doc));
        await engine.close(doc);
      }
      expect(opened, greaterThan(0));
      final healthy = await openFile('two-column-article.pdf');
      expect(await engine.render(tile(healthy.handle)), isA<RenderedBitmap>());
    });
  });
}

Future<void> _ignoringDocumentErrors(Future<Object?> Function() call) async {
  try {
    await call();
  } on PdfEngineException catch (e) {
    if (e.kind != EngineErrorKind.documentError &&
        e.kind != EngineErrorKind.invalidPage) {
      rethrow;
    }
  }
}
