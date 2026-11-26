// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/reader/reader_controller.dart';
import 'package:doxa_pdf/features/reader/reader_geometry.dart';
import 'package:doxa_pdf/features/reader/reader_page.dart';
import 'package:doxa_pdf/features/reader/reader_view.dart';
import 'package:doxa_pdf/l10n/gen/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'test_images.dart';

/// Ten 400 × 600 pages labelled i, ii, 1..8, with an outline and links on
/// page 2: to page 7, to a web page and to another file.
FakeDocument book() => FakeDocument(
  pages: [
    for (var i = 0; i < 10; i++)
      FakePage(
        width: 400,
        height: 600,
        label: i == 0 ? 'i' : (i == 1 ? 'ii' : '${i - 1}'),
        links: i == 2
            ? const [
                PageLink(
                  PdfRect(50, 500, 150, 550),
                  GoToTarget(PdfDestination(7, y: 300)),
                ),
                PageLink(
                  PdfRect(50, 400, 150, 450),
                  UriTarget('https://example.org/'),
                ),
                PageLink(PdfRect(50, 300, 150, 350), UnsupportedTarget(2)),
              ]
            : const [],
      ),
  ],
  outline: const [
    OutlineNode(title: 'Preface', target: GoToTarget(PdfDestination(0))),
    OutlineNode(
      title: 'Chapter 1',
      target: GoToTarget(PdfDestination(2)),
      children: [
        OutlineNode(
          title: 'Section 1.1',
          target: GoToTarget(PdfDestination(4, y: 300)),
        ),
      ],
    ),
  ],
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<ReaderController> controllerFor(WidgetTester tester) async {
  final engine = FakePdfEngine({'book.pdf': book()});
  final opened =
      await engine.open(const FileSource('book.pdf')) as DocumentOpened;
  final decoder = await FakeDecoder.create(tester);
  final controller = ReaderController(
    engine: engine,
    document: opened.handle,
    info: opened.info,
    decoder: decoder.call,
  )..resize(const Size(400, 600), 1);
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group('controller', () {
    testWidgets('labels and page input (FR-VIEW-009, FR-VIEW-014)', (
      tester,
    ) async {
      final c = await controllerFor(tester);
      expect(c.pageLabel(1), 'ii');
      expect(c.pageLabel(9), '8');
      expect(c.parsePageInput('II'), 1);
      expect(c.parsePageInput(' 3 '), 4); // The label "3" wins.
      expect(c.parsePageInput('10'), 9); // No label "10": page number 10.
      expect(c.parsePageInput('11'), isNull);
      expect(c.parsePageInput('xyz'), isNull);
      expect(c.parsePageInput(''), isNull);
      await settle(tester);
    });

    testWidgets('jumps to destinations and walks the history (FR-VIEW-011)', (
      tester,
    ) async {
      final c = await controllerFor(tester);
      expect(c.canGoBack, isFalse);
      await c.goToDestination(const PdfDestination(7, y: 300));
      // y = 300 in a 600 pt page is the middle of page 7 (1 unit per pt).
      final page = c.layout!.pageRect(7);
      expect(c.offset.dy, closeTo(page.top + 300, 1e-9));
      expect(c.currentPage, 7);
      expect(c.canGoBack, isTrue);
      c.goToPage(3, record: true);
      c.goBack();
      expect(c.currentPage, 7);
      c.goBack();
      expect(c.offset, Offset.zero);
      expect(c.canGoForward, isTrue);
      c.goForward();
      expect(c.currentPage, 7);
      // A plain scroll is not a jump.
      c.panBy(const Offset(0, -100));
      expect(c.canGoForward, isTrue);
      // History survives a layout switch and a resize (the keyboard of
      // "Go to page" closing, a rotation).
      c.setOptions(const ReaderOptions(mode: ReaderMode.singlePage));
      c.resize(const Size(400, 500), 1);
      expect(c.canGoBack, isTrue);
      c.goBack();
      expect(c.currentPage, 0);
      // Releasing the scrubber on the current page is not a jump.
      c.goToPage(0, record: true);
      expect(c.canGoForward, isTrue);
      await settle(tester);
    });

    testWidgets('a destination without a top starts the rotated page', (
      tester,
    ) async {
      final engine = FakePdfEngine({
        'r.pdf': FakeDocument(
          pages: [
            for (var i = 0; i < 3; i++)
              const FakePage(width: 400, height: 600, rotation: 180),
          ],
        ),
      });
      final opened =
          await engine.open(const FileSource('r.pdf')) as DocumentOpened;
      final decoder = await FakeDecoder.create(tester);
      final c = ReaderController(
        engine: engine,
        document: opened.handle,
        info: opened.info,
        decoder: decoder.call,
      )..resize(const Size(400, 300), 1);
      addTearDown(c.dispose);
      await c.goToDestination(const PdfDestination(1, x: 72));
      expect(c.offset.dy, closeTo(c.layout!.pageRect(1).top, 1e-9));
      await settle(tester);
    });

    testWidgets('a document without pages opens', (tester) async {
      final engine = FakePdfEngine({
        'empty.pdf': const FakeDocument(pages: []),
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReaderPage(
            engine: Future.value(engine),
            source: const FileSource('empty.pdf'),
            title: 'empty.pdf',
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderView), findsOneWidget);
      expect(find.byTooltip('Contents'), findsNothing);
    });

    testWidgets('finds links under a tap (FR-VIEW-010)', (tester) async {
      final c = await controllerFor(tester);
      c.goToPage(2);
      // PDF (100, 525) on page 2 is 75 px from its top: screen (100, 75).
      final target = await c.linkAt(const Offset(100, 75));
      expect((target! as GoToTarget).destination.pageIndex, 7);
      expect(await c.linkAt(const Offset(100, 175)), isA<UriTarget>());
      expect(await c.linkAt(const Offset(300, 75)), isNull);
      await settle(tester);
    });

    testWidgets('requests thumbnails at thumbnail priority', (tester) async {
      final c = await controllerFor(tester);
      final engine = c.engine as FakePdfEngine;
      expect(c.thumbnail(9), isNull);
      await settle(tester);
      expect(c.thumbnail(9), isNotNull);
      expect(
        engine.renderLog.where((r) => r.pageIndex == 9).map((r) => r.priority),
        contains(RenderPriority.thumbnail),
      );
    });
  });

  group('page', () {
    late List<String> opened;

    Future<void> show(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(800, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      opened = [];
      final decoder = await FakeDecoder.create(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: ReaderPage(
            engine: Future.value(FakePdfEngine({'book.pdf': book()})),
            source: const FileSource('book.pdf'),
            title: 'book.pdf',
            decoder: decoder.call,
            openUri: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      );
      await settle(tester);
    }

    ReaderController controllerOf(WidgetTester tester) =>
        tester.widget<ReaderView>(find.byType(ReaderView)).controller;

    testWidgets('shows the page label and goes to a typed page', (
      tester,
    ) async {
      await show(tester);
      expect(find.text('i (1 of 10)'), findsOneWidget);
      await tester.tap(find.text('i (1 of 10)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(
        find.text('There is no page “nope” in this document.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '5');
      await tester.tap(find.text('Go'));
      await settle(tester);
      expect(find.text('5 (7 of 10)'), findsOneWidget);
      // The jump can be undone (FR-VIEW-011).
      await tester.tap(find.byTooltip('Back to previous position'));
      await settle(tester);
      expect(find.text('i (1 of 10)'), findsOneWidget);
    });

    testWidgets('back leaves the document even after a jump', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final decoder = await FakeDecoder.create(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReaderPage(
                    engine: Future.value(FakePdfEngine({'book.pdf': book()})),
                    source: const FileSource('book.pdf'),
                    title: 'book.pdf',
                    decoder: decoder.call,
                  ),
                ),
              ),
              child: const Text('Home'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Home'));
      await settle(tester);
      controllerOf(tester).goToPage(6, record: true);
      await settle(tester);
      expect(controllerOf(tester).canGoBack, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('the outline and thumbnails navigate (FR-VIEW-007/008)', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      expect(find.text('Preface'), findsOneWidget);
      // The title opens the chapter; the arrow shows its sections.
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Section 1.1'));
      await settle(tester);
      expect(find.text('3 (5 of 10)'), findsOneWidget);

      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ii'));
      await settle(tester);
      expect(find.text('ii (2 of 10)'), findsOneWidget);
    });

    testWidgets('external links ask first (FR-VIEW-010)', (tester) async {
      final copied = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied.add(call.arguments);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await show(tester);
      final page = find.text('i (1 of 10)');
      await tester.tap(page);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.text('Go'));
      await settle(tester);
      // Page 2 fills the 800 px width: 2 px per pt. The web link is at
      // PDF (100, 425): screen (200, (600 - 425) * 2) below the app bar.
      final reader = tester.getTopLeft(find.byType(ReaderView));
      await tester.tapAt(reader + const Offset(200, 350));
      await settle(tester);
      expect(find.text('Open this link in another app?'), findsOneWidget);
      expect(find.text('https://example.org/'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(opened, ['https://example.org/']);

      await tester.tapAt(reader + const Offset(200, 350));
      await settle(tester);
      await tester.tap(find.text('Copy link'));
      await settle(tester);
      expect(find.text('Link copied.'), findsOneWidget);
      expect(copied.single, {'text': 'https://example.org/'});
      expect(opened, hasLength(1));
    });

    testWidgets('a failing link opener shows a message', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final decoder = await FakeDecoder.create(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: ReaderPage(
            engine: Future.value(FakePdfEngine({'book.pdf': book()})),
            source: const FileSource('book.pdf'),
            title: 'book.pdf',
            decoder: decoder.call,
            openUri: (uri) async => throw PlatformException(code: 'channel'),
          ),
        ),
      );
      await settle(tester);
      controllerOf(tester).goToPage(2);
      await settle(tester);
      final reader = tester.getTopLeft(find.byType(ReaderView));
      await tester.tapAt(reader + const Offset(200, 350));
      await settle(tester);
      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(find.text('No app can open this link.'), findsOneWidget);
    });

    testWidgets('internal links jump; foreign links explain', (tester) async {
      await show(tester);
      controllerOf(tester).goToPage(2);
      await settle(tester);
      final reader = tester.getTopLeft(find.byType(ReaderView));
      await tester.tapAt(reader + const Offset(200, 150)); // To page 7.
      await settle(tester);
      expect(find.text('6 (8 of 10)'), findsOneWidget);
      controllerOf(tester).goToPage(2);
      await settle(tester);
      await tester.tapAt(reader + const Offset(200, 550)); // Another file.
      await settle(tester);
      expect(
        find.text(
          'This link leads outside this document and cannot be followed.',
        ),
        findsOneWidget,
      );
    });
  });
}
