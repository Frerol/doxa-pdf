// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/reader/reader_controller.dart';
import 'package:doxa_pdf/features/reader/reader_geometry.dart';
import 'package:doxa_pdf/features/reader/reader_page.dart';
import 'package:doxa_pdf/features/reader/reader_view.dart';
import 'package:doxa_pdf/l10n/gen/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'test_images.dart';

const viewSize = Size(800, 616);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<ReaderController> controllerFor(
  WidgetTester tester, {
  ReaderOptions options = const ReaderOptions(mode: ReaderMode.singlePage),
  int pages = 10,
}) async {
  final engine = FakePdfEngine({
    'book.pdf': FakeDocument(
      pages: List.filled(pages, const FakePage(width: 400, height: 600)),
    ),
  });
  final opened =
      await engine.open(const FileSource('book.pdf')) as DocumentOpened;
  final decoder = await FakeDecoder.create(tester);
  final controller = ReaderController(
    engine: engine,
    document: opened.handle,
    info: opened.info,
    decoder: decoder.call,
    options: options,
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group('controller', () {
    testWidgets('turns pages forward and back, and stops at the ends', (
      tester,
    ) async {
      final c = await controllerFor(tester)
        ..resize(viewSize, 1);
      expect(c.currentPage, 0);
      expect(c.turnPage(forward: false), isNull);
      c.setView(c.turnPage(forward: true)!);
      expect(c.currentPage, 1);
      expect(c.offset, const Offset(800, 0));
      c.goToPage(9);
      expect(c.turnPage(forward: true), isNull);
      await settle(tester);
    });

    testWidgets('reading right to left turns forward to the left', (
      tester,
    ) async {
      final c =
          await controllerFor(
              tester,
              options: const ReaderOptions(
                mode: ReaderMode.singlePage,
                rightToLeft: true,
              ),
            )
            ..resize(viewSize, 1);
      // Page 0 is the rightmost cell.
      expect(c.currentPage, 0);
      expect(c.offset.dx, 9 * 800);
      final next = c.turnPage(forward: true)!;
      expect(next.offset.dx, 8 * 800);
      expect(c.turn(towardsLeft: true)!.offset, next.offset);
      await settle(tester);
    });

    testWidgets('a quick swipe turns one page; a slow drag settles back', (
      tester,
    ) async {
      final c = await controllerFor(tester)
        ..resize(viewSize, 1);
      c.panBy(const Offset(-100, 0));
      expect(
        c.settle(startSpread: 0, velocity: Offset.zero)!.offset,
        Offset.zero,
      );
      final turned = c.settle(
        startSpread: 0,
        velocity: const Offset(-1500, 0),
      )!;
      expect(turned.offset, const Offset(800, 0));
      // Dragging past the middle of the screen also turns.
      c.setView((zoom: 1, offset: const Offset(500, 0), atFit: true));
      expect(
        c.settle(startSpread: 0, velocity: Offset.zero)!.offset,
        const Offset(800, 0),
      );
      await settle(tester);
    });

    testWidgets('keeps or resets the zoom when turning (FR-VIEW-018)', (
      tester,
    ) async {
      final c = await controllerFor(tester)
        ..resize(viewSize, 1);
      c.zoomAround(2, const Offset(400, 308), const Offset(400, 308));
      final kept = c.turnPage(forward: true)!;
      expect(kept.zoom, c.zoom);
      expect(kept.offset.dx - 800, closeTo(c.offset.dx, 1e-9));
      c.setOptions(c.options.copyWith(keepZoomOnTurn: false));
      expect(c.turnPage(forward: true)!.atFit, isTrue);
      await settle(tester);
    });

    testWidgets('a zoomed-in swipe pans instead of turning', (tester) async {
      final c = await controllerFor(tester)
        ..resize(viewSize, 1);
      c.zoomAround(2, Offset.zero, Offset.zero);
      c.panBy(const Offset(-500, 0));
      // Inside the page: a fast swipe does not turn it, nothing moves.
      expect(
        c.settle(startSpread: 0, velocity: const Offset(-3000, 0)),
        isNull,
      );
      expect(c.currentSpread, 0);
      // Past the edge into the next page, the view settles inside it.
      c.panBy(const Offset(-900, 0));
      final view = c.settle(startSpread: 0, velocity: Offset.zero)!;
      expect(view.offset.dx, greaterThanOrEqualTo(800));
      await settle(tester);
    });

    testWidgets('switching layout keeps the current page', (tester) async {
      final c = await controllerFor(tester, options: const ReaderOptions())
        ..resize(viewSize, 1);
      c.goToPage(6);
      c.setOptions(const ReaderOptions(mode: ReaderMode.twoPages));
      expect(c.layout, isA<StripLayout>());
      // Cover, then [1,2] [3,4] [5,6]: page 6 is in the fourth spread.
      expect(c.currentSpread, 3);
      expect(c.layout!.pagesOf(c.currentSpread), contains(6));
      c.setOptions(const ReaderOptions(mode: ReaderMode.horizontal));
      expect(c.currentPage, inInclusiveRange(5, 6));
      c.setOptions(const ReaderOptions());
      expect(c.currentPage, inInclusiveRange(5, 6));
      await settle(tester);
    });

    testWidgets(
      'fit includes both pages of a spread after resize (FR-VIEW-004)',
      (tester) async {
        final c =
            await controllerFor(
                tester,
                options: const ReaderOptions(
                  mode: ReaderMode.twoPages,
                  coverPage: false,
                ),
              )
              ..resize(viewSize, 1);
        c.resize(const Size(640, 250), 1);
        Rect spread() =>
            c.layout!.pageRect(0).expandToInclude(c.layout!.pageRect(1));
        expect(c.visibleRect.inflate(1e-6).intersect(spread()), spread());
        c.setFitMode(FitMode.width);
        final view = c.visibleRect;
        expect(view.left, closeTo(spread().left, 1e-6));
        expect(view.width, closeTo(spread().width, 1e-6));
        await settle(tester);
      },
    );

    testWidgets('fit page and fit width in a paged layout', (tester) async {
      final c = await controllerFor(tester)
        ..resize(viewSize, 1);
      c.fitWidth();
      expect(c.zoom, 2); // A 400 px page fills 800 px.
      c.fitPage();
      expect(c.zoom, 1);
      expect(c.offset, Offset.zero);
      await settle(tester);
    });
  });

  group('resizing keeps the reading position', () {
    testWidgets('continuous: the zoomed-in column stays in view', (
      tester,
    ) async {
      final c = await controllerFor(tester, options: const ReaderOptions())
        ..resize(const Size(400, 600), 1);
      c.goToPage(3);
      c.zoomAround(2.5, const Offset(300, 0) + c.offset, const Offset(0, 0));
      final before = c.toDocument(Offset.zero);
      final page = c.layout!.pageRect(3);
      final fx = (before.dx - page.left) / page.width;
      c.resize(const Size(800, 500), 1); // Rotate.
      final after = c.toDocument(Offset.zero);
      final newPage = c.layout!.pageRect(3);
      expect((after.dx - newPage.left) / newPage.width, closeTo(fx, 1e-9));
      await settle(tester);
    });

    testWidgets('horizontal: a height change keeps the zoom', (tester) async {
      final c =
          await controllerFor(
              tester,
              options: const ReaderOptions(mode: ReaderMode.horizontal),
            )
            ..resize(viewSize, 1);
      c.goToPage(4);
      c.zoomTo(3);
      final page = c.currentPage;
      c.resize(const Size(800, 560), 1); // The system bars appear.
      expect(c.zoom, 3);
      expect(c.currentPage, page);
      await settle(tester);
    });
  });

  group('view', () {
    late ReaderController controller;

    Future<void> show(WidgetTester tester, ReaderOptions options) async {
      tester.view
        ..physicalSize = viewSize
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      controller = await controllerFor(tester, options: options);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: ReaderView(controller: controller)),
        ),
      );
      await settle(tester);
    }

    testWidgets('a swipe turns the page with an animation', (tester) async {
      await show(tester, const ReaderOptions(mode: ReaderMode.singlePage));
      await tester.flingFrom(
        const Offset(600, 300),
        const Offset(-200, 0),
        2000,
      );
      await settle(tester);
      expect(controller.currentPage, 1);
      expect(controller.offset, const Offset(800, 0));
    });

    testWidgets('tapping the edges turns pages (FR-VIEW-017)', (tester) async {
      await show(tester, const ReaderOptions(mode: ReaderMode.singlePage));
      Future<void> tapAt(double x) async {
        await tester.tapAt(Offset(x, 300));
        await settle(tester);
      }

      await tapAt(780);
      expect(controller.currentPage, 1);
      await tapAt(20);
      expect(controller.currentPage, 0);
      await tapAt(400); // The middle does nothing.
      expect(controller.currentPage, 0);

      controller.setOptions(controller.options.copyWith(tapZones: false));
      await tapAt(780);
      expect(controller.currentPage, 0);
    });

    testWidgets('an edge tap turns before the double-tap timeout', (
      tester,
    ) async {
      await show(tester, const ReaderOptions(mode: ReaderMode.singlePage));
      await tester.tapAt(const Offset(780, 300));
      // The 220 ms turn ends before the 300 ms double-tap timeout would.
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(controller.currentPage, 1);
      await settle(tester);
    });

    testWidgets('two quick edge taps turn two pages, not zoom', (tester) async {
      await show(tester, const ReaderOptions(mode: ReaderMode.singlePage));
      await tester.tapAt(const Offset(780, 300));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(780, 300));
      await settle(tester);
      expect(controller.zoom, 1);
      expect(controller.currentPage, 2);
    });

    testWidgets('the mouse wheel turns pages when paged', (tester) async {
      await show(tester, const ReaderOptions(mode: ReaderMode.singlePage));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(400, 300)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
      await settle(tester);
      expect(controller.currentPage, 1);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await settle(tester);
      expect(controller.currentPage, 0);
    });

    testWidgets('the mouse wheel scrolls a horizontal strip sideways', (
      tester,
    ) async {
      await show(tester, const ReaderOptions(mode: ReaderMode.horizontal));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(400, 300)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 150)));
      await settle(tester);
      expect(controller.offset.dx, 150);
    });

    testWidgets('the view options sheet switches the layout', (tester) async {
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
            engine: Future.value(
              FakePdfEngine({
                'book.pdf': FakeDocument(
                  pages: List.filled(5, const FakePage()),
                ),
              }),
            ),
            source: const FileSource('book.pdf'),
            title: 'book.pdf',
            decoder: decoder.call,
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.byTooltip('View options'));
      await tester.pumpAndSettle();
      // Right to left is off for the continuous layout.
      final rtl = find.widgetWithText(SwitchListTile, 'Right-to-left pages');
      expect(tester.widget<SwitchListTile>(rtl).onChanged, isNull);
      await tester.tap(find.text('Two pages'));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(rtl).onChanged, isNotNull);
      await tester.tap(rtl);
      await tester.pumpAndSettle();
      final view = tester.widget<ReaderView>(find.byType(ReaderView));
      expect(view.controller.options.mode, ReaderMode.twoPages);
      expect(view.controller.options.rightToLeft, isTrue);
      expect(view.controller.layout, isA<StripLayout>());
    });
  });
}
