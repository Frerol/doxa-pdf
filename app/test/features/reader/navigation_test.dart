// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/reader/navigation_panel.dart';
import 'package:doxa_pdf/features/reader/reader_chrome.dart';
import 'package:doxa_pdf/features/reader/reader_controller.dart';
import 'package:doxa_pdf/features/reader/reader_geometry.dart';
import 'package:doxa_pdf/features/reader/reader_page.dart';
import 'package:doxa_pdf/features/reader/reader_view.dart';
import 'package:doxa_pdf/features/reader/thumbnail_grid.dart';
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
      expect(find.byTooltip('Side panel'), findsNothing);
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

    Future<void> show(
      WidgetTester tester, {
      FakeDocument? document,
      PreferredSizeWidget? tabRow,
    }) async {
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
            engine: Future.value(
              FakePdfEngine({'book.pdf': document ?? book()}),
            ),
            source: const FileSource('book.pdf'),
            title: 'book.pdf',
            decoder: decoder.call,
            tabRow: tabRow,
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

    Offset linkPoint(WidgetTester tester, double pdfY) {
      final controller = controllerOf(tester);
      final page = controller.layout!.pageRect(2);
      final point = Offset(
        page.left + page.width * (100 / 400),
        page.top + page.height * ((600 - pdfY) / 600),
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      return origin + (point - controller.offset) * controller.zoom;
    }

    Future<void> openThumbnails(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Thumbnails'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'the thumbnail route jumps and keeps paged zoom (FR-VIEW-008)',
      (tester) async {
        await show(
          tester,
          tabRow: const PreferredSize(
            preferredSize: Size.fromHeight(32),
            child: Text('Document tabs'),
          ),
        );
        final controller = controllerOf(tester);
        controller.setOptions(const ReaderOptions(mode: ReaderMode.singlePage));
        controller.zoomTo(2.5);
        final zoom = controller.zoom;
        expect(zoom, greaterThan(1));
        await settle(tester);
        expect(find.text('Document tabs'), findsOneWidget);

        await openThumbnails(tester);
        expect(find.text('Thumbnails'), findsOneWidget);
        expect(find.byType(ReaderView).hitTestable(), findsNothing);
        expect(find.text('Document tabs').hitTestable(), findsNothing);
        final current = tester.widget<Text>(find.text('i'));
        expect(
          current.style?.color,
          Theme.of(tester.element(find.text('i'))).colorScheme.primary,
        );

        await tester.tap(find.text('ii'));
        await tester.pumpAndSettle();
        expect(find.byType(ThumbnailGrid), findsNothing);
        expect(find.text('Document tabs'), findsOneWidget);
        expect(find.text('ii (2 / 10)'), findsOneWidget);
        expect(controller.zoom, zoom);
      },
    );

    testWidgets('both Back controls close the grid in place (FR-VIEW-008)', (
      tester,
    ) async {
      await show(tester);
      controllerOf(tester).goToPage(2);
      await settle(tester);
      final position = find.text('1 (3 / 10)');

      await openThumbnails(tester);
      await tester.tap(find.byType(BackButton).hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(ThumbnailGrid), findsNothing);
      expect(position, findsOneWidget);

      await openThumbnails(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ThumbnailGrid), findsNothing);
      expect(position, findsOneWidget);
    });

    testWidgets('wider grids fit more thumbnails per row (FR-VIEW-008)', (
      tester,
    ) async {
      // The grid is its own page, so it can be opened on a wide screen and
      // then narrowed; the reader's app bar does not matter here.
      await show(tester);
      await openThumbnails(tester);
      tester.view.physicalSize = const Size(360, 800);
      await settle(tester);

      int firstRowCount() {
        final firstY = tester.getCenter(find.text('i')).dy;
        final labels = find.descendant(
          of: find.byType(GridView),
          matching: find.byType(Text),
        );
        return labels.evaluate().where((element) {
          final label = find.byElementPredicate((other) => other == element);
          return (tester.getCenter(label).dy - firstY).abs() < 0.1;
        }).length;
      }

      final phone = firstRowCount();
      tester.view.physicalSize = const Size(800, 1200);
      await settle(tester);
      final portrait = firstRowCount();
      expect(portrait, greaterThan(phone));
      tester.view.physicalSize = const Size(1280, 800);
      await settle(tester);
      expect(firstRowCount(), greaterThan(portrait));
    });

    testWidgets(
      'requests visible thumbnails near the current page (FR-VIEW-008)',
      (tester) async {
        await show(
          tester,
          document: FakeDocument(
            pages: List.filled(1001, const FakePage(width: 400, height: 600)),
          ),
        );
        final controller = controllerOf(tester);
        final engine = controller.engine as FakePdfEngine;
        controller.goToPage(710);
        await settle(tester);
        final before = engine.renderLog.length;
        await openThumbnails(tester);

        expect(find.text('711').hitTestable(), findsOneWidget);
        expect(find.text('1'), findsNothing);
        final grid = tester.getRect(find.byType(GridView));
        final visiblePages = <int>{};
        final cells = find.descendant(
          of: find.byType(GridView),
          matching: find.byType(InkWell),
        );
        for (final element in cells.evaluate()) {
          final cell = find.byElementPredicate((other) => other == element);
          if (!grid.overlaps(tester.getRect(cell))) continue;
          final label = tester.widget<Text>(
            find.descendant(of: cell, matching: find.byType(Text)),
          );
          visiblePages.add(int.parse(label.data!) - 1);
        }
        final requests = engine.renderLog.skip(before).toList();
        expect(requests, isNotEmpty);
        expect(
          requests.map((request) => request.priority),
          everyElement(RenderPriority.thumbnail),
        );
        expect(
          requests.map((request) => request.pageIndex),
          everyElement(isIn(visiblePages)),
        );
      },
    );

    testWidgets('shows the page label and goes to a typed page', (
      tester,
    ) async {
      await show(tester);
      expect(find.text('i (1 / 10)'), findsOneWidget);
      await tester.tap(find.text('i (1 / 10)'));
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
      expect(find.text('5 (7 / 10)'), findsOneWidget);
      // The jump can be undone (FR-VIEW-011).
      await tester.tap(find.byTooltip('Back to previous position'));
      await settle(tester);
      expect(find.text('i (1 / 10)'), findsOneWidget);
    });

    testWidgets('the indicator names the last page of a spread (#109)', (
      tester,
    ) async {
      await show(tester);
      final controller = controllerOf(tester);
      controller.setOptions(
        const ReaderOptions(mode: ReaderMode.twoPages, coverPage: false),
      );
      controller.goToPage(2);
      await settle(tester);
      // Pages 3 and 4 (labels 1 and 2) are on screen.
      expect(find.text('2 (4 / 10)'), findsOneWidget);
      expect(find.text('1 (3 / 10)'), findsNothing);
    });

    for (final mode in [ReaderMode.continuous, ReaderMode.singlePage]) {
      testWidgets('dragging the scrubber turns pages live, one jump back '
          '(${mode.name}, #109)', (tester) async {
        await show(tester);
        final controller = controllerOf(tester);
        controller.setOptions(ReaderOptions(mode: mode));
        await settle(tester);
        final area = tester.getRect(find.byType(ReaderScrubber));
        final grip = find.descendant(
          of: find.byType(ReaderScrubber),
          matching: find.byType(GestureDetector),
        );
        final vertical = mode == ReaderMode.continuous;
        // Scrolling continuously, the grip sits on the right edge.
        if (vertical) {
          expect(tester.getCenter(grip).dx, greaterThan(area.center.dx));
        } else {
          expect(tester.getCenter(grip).dy, greaterThan(area.center.dy));
        }

        final drag = await tester.startGesture(tester.getCenter(grip));
        final end = area.bottomRight;
        for (var i = 1; i <= 4; i++) {
          final to = vertical
              ? Offset(
                  tester.getCenter(grip).dx,
                  area.top + area.height * i / 8,
                )
              : Offset(
                  area.left + area.width * i / 8,
                  tester.getCenter(grip).dy,
                );
          await drag.moveTo(to);
          await tester.pump();
        }
        // Pages turn while the finger is still down.
        final midway = controller.currentPage;
        expect(midway, greaterThan(1));
        await drag.moveTo(
          vertical
              ? Offset(tester.getCenter(grip).dx, end.dy)
              : Offset(end.dx, tester.getCenter(grip).dy),
        );
        await tester.pump();
        await drag.up();
        await settle(tester);
        expect(controller.currentPage, greaterThan(midway));

        // The whole drag is one jump: Back returns to the first page.
        controller.goBack();
        await settle(tester);
        expect(controller.currentPage, 0);
        expect(controller.canGoBack, isFalse);
      });
    }

    testWidgets('the scrubber and history stay clear of the taskbar (#109)', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetPadding);
      await show(tester);
      final controller = controllerOf(tester);
      controller.setOptions(const ReaderOptions(mode: ReaderMode.singlePage));
      controller.goToPage(5, record: true);
      await settle(tester);
      final screen = tester.view.physicalSize.height;
      final grip = find.descendant(
        of: find.byType(ReaderScrubber),
        matching: find.byType(GestureDetector),
      );
      expect(tester.getRect(grip).bottom, lessThanOrEqualTo(screen - 48));
      expect(
        tester.getRect(find.byType(ReaderHistoryControl)).bottom,
        lessThanOrEqualTo(screen - 48),
      );
    });

    testWidgets('the history control shows after a jump, then fades (#109)', (
      tester,
    ) async {
      await show(tester);
      expect(find.byTooltip('Back to previous position'), findsNothing);
      controllerOf(tester).goToPage(5, record: true);
      await settle(tester);
      expect(find.byTooltip('Back to previous position'), findsOneWidget);
      double opacity() => tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.byTooltip('Back to previous position'),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      expect(opacity(), 1);
      await tester.pump(ReaderHistoryControl.idleAfter * 2);
      await tester.pumpAndSettle();
      expect(opacity(), lessThan(1));
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

    testWidgets('contents jumps leave the tablet panel open (FR-VIEW-007)', (
      tester,
    ) async {
      await show(tester);
      tester.view.physicalSize = const Size(1280, 800);
      await settle(tester);
      await tester.tap(find.byTooltip('Side panel'));
      await settle(tester);

      expect(find.text('Contents'), findsOneWidget);
      expect(find.text('Preface'), findsOneWidget);
      expect(find.byTooltip('Pages'), findsNothing);
      expect(find.text('ii'), findsNothing);
      expect(find.text('Section 1.1'), findsNothing);
      final chapter = find.text('Chapter 1');
      final panel = find.byType(ReaderSidePanel);
      final chapterPage = find.descendant(of: panel, matching: find.text('1'));
      expect(
        tester.getCenter(chapterPage).dx,
        greaterThan(tester.getCenter(chapter).dx),
      );

      await tester.tap(find.byTooltip('Expand entry'));
      await settle(tester);
      final child = find.text('Section 1.1');
      expect(
        tester.getTopLeft(child).dx,
        greaterThan(tester.getTopLeft(find.text('Preface')).dx),
      );
      await tester.tap(child);
      await settle(tester);
      expect(find.text('3 (5 / 10)'), findsOneWidget);
      expect(panel, findsOneWidget);
    });

    testWidgets('contents can expand, collapse and find nested entries', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.byTooltip('Side panel'));
      await settle(tester);
      await tester.tap(find.byTooltip('Expand all'));
      await settle(tester);
      expect(find.text('Section 1.1'), findsOneWidget);
      await tester.tap(find.byTooltip('Collapse all'));
      await settle(tester);
      expect(find.text('Section 1.1'), findsNothing);
      await tester.tap(find.byTooltip('Search contents'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'SECTION');
      await settle(tester);
      expect(find.text('Section 1.1'), findsOneWidget);
      expect(find.text('Preface'), findsNothing);
    });

    testWidgets(
      'the left dock narrows the reader and refits the page (UX §7)',
      (tester) async {
        await show(tester);
        final view = find.byType(ReaderView);
        final panel = find.byType(ReaderSidePanel);
        final controller = controllerOf(tester);
        final fullViewport = tester.getRect(view);
        final fullPageWidth = controller.layout!.pageRect(0).width;

        await tester.tap(find.byTooltip('Side panel'));
        await settle(tester);
        final dockedViewport = tester.getRect(view);
        expect(
          tester.getRect(panel).right,
          lessThanOrEqualTo(dockedViewport.left),
        );
        expect(dockedViewport.right, fullViewport.right);
        expect(dockedViewport.width, lessThan(fullViewport.width));
        expect(controller.layout!.pageRect(0).width, lessThan(fullPageWidth));
        expect(
          controller.layout!.pageRect(0).width * controller.zoom,
          closeTo(dockedViewport.width, 1e-6),
        );

        await tester.tap(find.byTooltip('Close'));
        await settle(tester);
        expect(panel, findsNothing);
        expect(tester.getRect(view), fullViewport);
        expect(
          controller.layout!.pageRect(0).width,
          closeTo(fullPageWidth, 1e-6),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('docking reapplies an explicit fit-page view', (tester) async {
      await show(tester);
      final controller = controllerOf(tester);
      controller.fitPage();
      final fitted = controller.layout!.pageRect(0).width * controller.zoom;
      await tester.tap(find.byTooltip('Side panel'));
      await settle(tester);

      final page = controller.layout!.pageRect(0);
      expect(page.width * controller.zoom, lessThan(fitted));
      expect(
        page.width * controller.zoom,
        closeTo(controller.viewSize.width, 1e-6),
      );
    });

    testWidgets(
      'docking clips a zoomed page without changing its scale or position',
      (tester) async {
        await show(tester);
        final controller = controllerOf(tester);
        controller.goToPage(2);
        controller.zoomTo(2.5);
        await settle(tester);
        // Where page 3 sits on the screen, and how wide it is there.
        Rect onScreen() {
          final rect = controller.layout!.pageRect(2);
          return Rect.fromPoints(
            (rect.topLeft - controller.offset) * controller.zoom,
            (rect.bottomRight - controller.offset) * controller.zoom,
          );
        }

        final before = onScreen();
        final pageWidth = before.width;
        void expectSameView() {
          final now = onScreen();
          expect(now.width, closeTo(before.width, 1e-6));
          expect(now.left, closeTo(before.left, 1e-6));
          expect(now.top, closeTo(before.top, 1e-6));
        }

        await tester.tap(find.byTooltip('Side panel'));
        await settle(tester);
        expectSameView();
        expect(controller.viewSize.width, lessThan(pageWidth));

        await tester.tap(find.byTooltip('Side panel'));
        await settle(tester);
        expectSameView();
      },
    );

    testWidgets('on phones a contents jump closes the full-screen route', (
      tester,
    ) async {
      await show(tester);
      tester.view.physicalSize = const Size(400, 800);
      await settle(tester);
      await tester.tap(find.byTooltip('Side panel'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSidePanel), findsOneWidget);
      expect(find.byType(ReaderView), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.text('Chapter 1'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSidePanel), findsNothing);
      expect(find.text('1 (3 / 10)'), findsOneWidget);
    });

    testWidgets('system Back closes phone contents and returns to the reader', (
      tester,
    ) async {
      await show(tester);
      tester.view.physicalSize = const Size(400, 800);
      await settle(tester);
      final controller = controllerOf(tester);
      controller.goToPage(6);
      await settle(tester);
      await tester.tap(find.byTooltip('Side panel'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSidePanel), findsNothing);
      expect(controllerOf(tester), same(controller));
      expect(find.text('5 (7 / 10)'), findsOneWidget);
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
      final page = find.text('i (1 / 10)');
      await tester.tap(page);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.text('Go'));
      await settle(tester);
      await tester.tapAt(linkPoint(tester, 425));
      await settle(tester);
      expect(find.text('Open this link in another app?'), findsOneWidget);
      expect(find.text('https://example.org/'), findsOneWidget);
      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(opened, ['https://example.org/']);

      await tester.tapAt(linkPoint(tester, 425));
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
      await tester.tapAt(linkPoint(tester, 425));
      await settle(tester);
      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(find.text('No app can open this link.'), findsOneWidget);
    });

    testWidgets('internal links jump; foreign links explain', (tester) async {
      await show(tester);
      controllerOf(tester).goToPage(2);
      await settle(tester);
      await tester.tapAt(linkPoint(tester, 525)); // To page 7.
      await settle(tester);
      expect(find.text('6 (8 / 10)'), findsOneWidget);
      controllerOf(tester).goToPage(2);
      await settle(tester);
      await tester.tapAt(linkPoint(tester, 325)); // Another file.
      await settle(tester);
      expect(
        find.text(
          'This link leads outside this document and cannot be followed.',
        ),
        findsOneWidget,
      );
    });

    group('a tap in the middle of the page (#95)', () {
      late List<String> modes;

      setUp(() {
        modes = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
                modes.add(call.arguments as String);
              }
              return null;
            });
      });

      tearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      Future<void> tapMiddle(WidgetTester tester) async {
        await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
        await settle(tester);
      }

      testWidgets('hides and shows the bars outside full screen', (
        tester,
      ) async {
        await show(tester);
        final shownHeight = tester.getSize(find.byType(ReaderView)).height;
        expect(find.byType(AppBar), findsOneWidget);

        expect(find.byType(ReaderPageIndicator), findsOneWidget);
        expect(find.byType(ReaderScrubber), findsOneWidget);

        await tapMiddle(tester);
        expect(find.byType(AppBar), findsNothing);
        // The page controls hide with the bars (#109).
        expect(find.byType(ReaderPageIndicator), findsNothing);
        expect(find.byType(ReaderScrubber), findsNothing);
        expect(modes.last, SystemUiMode.immersiveSticky.toString());
        // The page gets the room the bars leave.
        expect(
          tester.getSize(find.byType(ReaderView)).height,
          greaterThan(shownHeight),
        );

        await tapMiddle(tester);
        expect(find.byType(AppBar), findsOneWidget);
        expect(modes.last, SystemUiMode.edgeToEdge.toString());
        expect(tester.getSize(find.byType(ReaderView)).height, shownHeight);
      });

      testWidgets('a tap on a link follows it and keeps the bars', (
        tester,
      ) async {
        await show(tester);
        controllerOf(tester).goToPage(2);
        await settle(tester);
        await tester.tapAt(linkPoint(tester, 525)); // To page 7.
        await settle(tester);
        expect(find.text('6 (8 / 10)'), findsOneWidget);
        expect(modes, isEmpty);
      });

      testWidgets('the side panel stays open while the bars hide', (
        tester,
      ) async {
        await show(tester);
        tester.view.physicalSize = const Size(1280, 800);
        await settle(tester);
        await tester.tap(find.byTooltip('Side panel'));
        await settle(tester);

        await tapMiddle(tester);
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(ReaderSidePanel), findsOneWidget);
      });
    });
  });
}
