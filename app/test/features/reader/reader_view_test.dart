// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/reader/reader_controller.dart';
import 'package:doxa_pdf/features/reader/reader_page.dart';
import 'package:doxa_pdf/features/reader/reader_view.dart';
import 'package:doxa_pdf/features/settings/app_settings.dart';
import 'package:doxa_pdf/features/settings/settings_page.dart';
import 'package:doxa_pdf/l10n/gen/app_localizations.dart';
import 'package:doxa_pdf/src/doxa_app.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import 'test_images.dart';

FakePdfEngine fakeEngine() => FakePdfEngine({
  'book.pdf': FakeDocument(
    pages: List.filled(40, const FakePage(width: 400, height: 600)),
  ),
  'secret.pdf': const FakeDocument(pages: [FakePage()], password: 'study'),
});

Widget localized(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: child,
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late ReaderController controller;

  Future<void> showReader(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(400, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = fakeEngine();
    final opened =
        await engine.open(const FileSource('book.pdf')) as DocumentOpened;
    final decoder = await FakeDecoder.create(tester);
    controller = ReaderController(
      engine: engine,
      document: opened.handle,
      info: opened.info,
      decoder: decoder.call,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      localized(Scaffold(body: ReaderView(controller: controller))),
    );
    await settle(tester);
  }

  testWidgets('a finger drag scrolls, a stylus drag does not (ADR-0006)', (
    tester,
  ) async {
    await showReader(tester);
    expect(controller.offset.dy, 0);

    final pen = await tester.startGesture(
      const Offset(200, 400),
      kind: PointerDeviceKind.stylus,
    );
    for (var i = 0; i < 10; i++) {
      await pen.moveBy(const Offset(0, -20));
    }
    await pen.up();
    await settle(tester);
    expect(controller.offset.dy, 0);

    await tester.dragFrom(const Offset(200, 400), const Offset(0, -200));
    await settle(tester);
    expect(controller.offset.dy, greaterThan(150));
  });

  testWidgets('a fling keeps scrolling after the finger lifts', (tester) async {
    await showReader(tester);
    await tester.flingFrom(const Offset(200, 500), const Offset(0, -300), 3000);
    await settle(tester);
    expect(controller.offset.dy, greaterThan(300));
  });

  testWidgets('a pinch zooms', (tester) async {
    await showReader(tester);
    final a = await tester.startGesture(const Offset(150, 300));
    final b = await tester.startGesture(const Offset(250, 300));
    for (var i = 0; i < 5; i++) {
      await a.moveBy(const Offset(-10, 0));
      await b.moveBy(const Offset(10, 0));
    }
    await a.up();
    await b.up();
    await settle(tester);
    // The recognizer accepts the pinch after a few pixels of slop.
    expect(controller.zoom, greaterThan(1.4));
  });

  testWidgets('a double tap zooms in and out (FR-VIEW-004)', (tester) async {
    await showReader(tester);
    tester.view.physicalSize = const Size(400, 360);
    await tester.pump();
    final fit = controller.zoom;
    const point = Offset(200, 100);
    final documentPoint = controller.toDocument(point);
    Future<void> doubleTap() async {
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(point);
      await settle(tester);
    }

    await doubleTap();
    expect(controller.zoom, greaterThan(fit));
    expect(
      (controller.toDocument(point) - documentPoint).distance,
      closeTo(0, 1e-6),
    );
    await doubleTap();
    expect(controller.zoom, closeTo(fit, 1e-6));
  });

  testWidgets('the mouse wheel scrolls', (tester) async {
    await showReader(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(200, 300)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await settle(tester);
    expect(controller.offset.dy, 120);
  });

  testWidgets('memory pressure frees off-screen images', (tester) async {
    await showReader(tester);
    expect(
      controller.cache.length,
      greaterThan(controller.visibleKeys().length),
    );
    tester.binding.handleMemoryPressure();
    await tester.pump();
    expect(controller.cache.keys.toSet(), controller.visibleKeys());
  });

  group('ReaderPage', () {
    Future<void> showPage(
      WidgetTester tester,
      String path, {
      SettingsController? settings,
    }) async {
      final decoder = await FakeDecoder.create(tester);
      await tester.pumpWidget(
        localized(
          ReaderPage(
            key: ValueKey(path),
            engine: Future.value(fakeEngine()),
            source: FileSource(path),
            title: path,
            settings: settings,
            decoder: decoder.call,
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('opens with default width fit and no zoom menu (FR-VIEW-004)', (
      tester,
    ) async {
      await showPage(tester, 'book.pdf');
      final view = tester.widget<ReaderView>(find.byType(ReaderView));
      final reader = view.controller;
      final page = reader.layout!.pageRect(0);
      expect(reader.visibleRect.width, closeTo(page.width, 1e-6));
      expect(find.byTooltip('Zoom'), findsNothing);
      expect(find.byIcon(LucideIcons.zoomIn), findsNothing);
    });

    testWidgets(
      'the saved fit choice applies when opening a document (FR-VIEW-004)',
      (tester) async {
        final store = MemorySettingsStore();
        final settings = SettingsController(store);
        final restored = SettingsController(store);
        addTearDown(settings.dispose);
        addTearDown(restored.dispose);
        await tester.pumpWidget(localized(SettingsPage(settings: settings)));
        await tester.tap(find.text('Viewing'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Page fit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fit page'));
        await tester.pumpAndSettle();
        await settings.flush();
        await restored.load();
        // Drop the settings routes, or the reader opens beneath them.
        await tester.pumpWidget(const SizedBox());

        await showPage(tester, 'book.pdf', settings: restored);
        final reader = tester
            .widget<ReaderView>(find.byType(ReaderView))
            .controller;
        final page = reader.layout!.pageRect(0);
        expect(reader.visibleRect.height, closeTo(page.height, 1e-6));
        expect(reader.visibleRect.width, greaterThan(page.width));
      },
    );

    testWidgets('reports an engine that cannot start', (tester) async {
      await tester.pumpWidget(
        localized(
          ReaderPage(
            engine: Future<PdfEngine>.delayed(
              const Duration(milliseconds: 1),
              () => throw const PdfEngineException(
                EngineErrorKind.stopped,
                'no PDFium',
              ),
            ),
            source: const FileSource('book.pdf'),
            title: 'book.pdf',
          ),
        ),
      );
      await settle(tester);
      expect(find.text('This file could not be opened.'), findsOneWidget);
    });

    testWidgets('explains files it cannot open', (tester) async {
      await showPage(tester, 'missing.pdf');
      expect(find.text('The file could not be read.'), findsOneWidget);
      await showPage(tester, 'secret.pdf');
      expect(
        find.text('This PDF is protected with a password.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the developer list opens PDFs from its folder', (tester) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('doxa-dev-docs-'),
    );
    addTearDown(() => dir!.deleteSync(recursive: true));
    File('${dir!.path}/book.pdf').writeAsStringSync('placeholder');
    File('${dir.path}/notes.txt').writeAsStringSync('ignored');
    final engine = FakePdfEngine({
      '${dir.path}/book.pdf': const FakeDocument(pages: [FakePage()]),
    });
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      DoxaApp(engine: () async => engine, devDocumentsDir: dir.path),
    );
    await tester.tap(find.byTooltip('PDFs in the app folder (developer)'));
    await tester.pumpAndSettle();
    expect(find.text('book.pdf'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
    await tester.tap(find.text('book.pdf'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPage), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
  });
}
