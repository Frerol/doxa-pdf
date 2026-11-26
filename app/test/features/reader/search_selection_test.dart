// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/dictionary/dictionary_library.dart';
import 'package:doxa_pdf/features/reader/reader_controller.dart';
import 'package:doxa_pdf/features/reader/reader_geometry.dart';
import 'package:doxa_pdf/features/reader/reader_page.dart';
import 'package:doxa_pdf/features/reader/reader_view.dart';
import 'package:doxa_pdf/features/reader/search_session.dart';
import 'package:doxa_pdf/features/reader/text_selection.dart';
import 'package:doxa_pdf/l10n/gen/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'test_images.dart';

// FakePdfEngine boxes: char i spans x 72 + 10i .. 82 + 10i and y 700..712
// in PDF user space. With a 612 × 792 page shown 612 px wide (1 px per pt),
// char i is centred at screen (77 + 10i, 86) on the first page.
Offset charCentre(int i) => Offset(77 + 10.0 * i, 86);

FakeDocument doc() => FakeDocument(
  pages: [
    const FakePage(text: 'hello world, ação'),
    for (var i = 1; i < 6; i++)
      FakePage(text: i.isEven ? 'acao here' : 'nothing'),
  ],
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<ReaderController> controllerFor(WidgetTester tester) async {
  final engine = FakePdfEngine({'doc.pdf': doc()});
  final opened =
      await engine.open(const FileSource('doc.pdf')) as DocumentOpened;
  final decoder = await FakeDecoder.create(tester);
  final controller = ReaderController(
    engine: engine,
    document: opened.handle,
    info: opened.info,
    decoder: decoder.call,
  )..resize(const Size(612, 792), 1);
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group('SearchSession (FR-TEXT-001)', () {
    testWidgets('streams hits, starts at the current page, wraps', (
      tester,
    ) async {
      final reader = await controllerFor(tester);
      final search = SearchSession(reader);
      addTearDown(search.dispose);
      reader.goToPage(3);
      search.start(const SearchQuery('acao'));
      expect(search.status.value.searching, isTrue);
      await settle(tester);
      final status = search.status.value;
      // "ação" on page 0, "acao" on pages 2 and 4.
      expect(status.count, 3);
      expect(status.searching, isFalse);
      expect(search.currentHit!.pageIndex, 4);
      expect(reader.highlights(HighlightLayer.searchHits, 2), isNotEmpty);
      expect(reader.highlights(HighlightLayer.currentHit, 4), isNotEmpty);
      search.next();
      expect(search.currentHit!.pageIndex, 0);
      search.previous();
      search.previous();
      expect(search.currentHit!.pageIndex, 2);
      await settle(tester);
      expect(reader.currentPage, 2);
      search.close();
      expect(reader.highlights(HighlightLayer.searchHits, 2), isEmpty);
      expect(search.status.value.active, isFalse);
    });

    testWidgets('previous before any hit after the start page', (tester) async {
      final reader = await controllerFor(tester);
      final search = SearchSession(reader);
      addTearDown(search.dispose);
      reader.goToPage(5);
      search.start(const SearchQuery('acao'));
      await settle(tester);
      // No hit on page 5: the search wrapped to the first hit.
      expect(search.currentHit!.pageIndex, 0);
      expect(search.isStale(const SearchQuery('acao')), isFalse);
      expect(search.isStale(const SearchQuery('acaox')), isTrue);
      search.update(const SearchQuery('acao'));
      expect(search.isStale(const SearchQuery('acao')), isTrue);
      await settle(tester);
    });

    testWidgets('a hit on another spread keeps the zoom', (tester) async {
      final reader = await controllerFor(tester);
      reader.setOptions(reader.options.copyWith(mode: ReaderMode.singlePage));
      reader.zoomTo(2);
      final search = SearchSession(reader);
      addTearDown(search.dispose);
      search.start(const SearchQuery('acao here'));
      await settle(tester);
      expect(reader.currentPage, 2);
      expect(reader.zoom, 2);
    });

    testWidgets('a new query replaces the old one', (tester) async {
      final reader = await controllerFor(tester);
      final search = SearchSession(reader);
      addTearDown(search.dispose);
      search.start(const SearchQuery('acao'));
      search.start(const SearchQuery('nothing'));
      await settle(tester);
      expect(search.status.value.count, 3);
      expect(search.hits.map((h) => h.pageIndex), [1, 3, 5]);
      search.start(const SearchQuery('zzz'));
      await settle(tester);
      expect(search.status.value.count, 0);
      expect(search.status.value.active, isTrue);
    });
  });

  group('TextSelectionController (FR-TEXT-004)', () {
    testWidgets('selects a word, extends it and copies it', (tester) async {
      final reader = await controllerFor(tester);
      final selection = TextSelectionController(reader);
      addTearDown(selection.dispose);
      expect(await selection.selectWordAt(charCentre(1)), isTrue);
      expect(selection.text, 'hello');
      await selection.extendTo(charCentre(8));
      expect(selection.text, 'hello wor');
      // Dragging back inside the word keeps the whole word.
      await selection.extendTo(charCentre(0));
      expect(selection.text, 'hello');
      expect(reader.highlights(HighlightLayer.selection, 0), hasLength(1));

      await selection.selectWordAt(charCentre(14));
      expect(selection.text, 'ação');
      selection
        ..beginHandleDrag(start: true)
        ..moveHandle(start: true, screenPoint: charCentre(6));
      expect(selection.text, 'world, ação');
      // Dragging the start handle past the end keeps the end fixed.
      selection
        ..beginHandleDrag(start: true)
        ..moveHandle(start: true, screenPoint: charCentre(16))
        ..moveHandle(start: true, screenPoint: charCentre(15));
      expect(selection.text, 'ão');
      selection.moveHandle(start: true, screenPoint: charCentre(6));
      expect(selection.text, 'world, ação');
      final (start, end) = selection.handles()!;
      expect(start.dx, closeTo(72 + 60, 1e-9));
      expect(end.dx, closeTo(82 + 160, 1e-9));
      selection.clear();
      expect(reader.highlights(HighlightLayer.selection, 0), isEmpty);
      await settle(tester);
    });

    testWidgets('finds nothing away from the text', (tester) async {
      final reader = await controllerFor(tester);
      final selection = TextSelectionController(reader);
      addTearDown(selection.dispose);
      expect(await selection.selectWordAt(const Offset(400, 600)), isFalse);
      expect(selection.hasSelection, isFalse);
      await settle(tester);
    });
  });

  group('page', () {
    Future<void> show(WidgetTester tester, {TransitionBuilder? builder}) async {
      tester.view
        ..physicalSize = const Size(612, 1000)
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
          builder: builder,
          home: ReaderPage(
            engine: Future.value(FakePdfEngine({'doc.pdf': doc()})),
            source: const FileSource('doc.pdf'),
            title: 'doc.pdf',
            decoder: decoder.call,
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('searches as you type and steps through hits', (tester) async {
      await show(tester);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Acao');
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);
      expect(find.text('1 of 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Next result'));
      await settle(tester);
      expect(find.text('2 of 3'), findsOneWidget);
      // Match case: "Acao" is nowhere with a capital A.
      await tester.tap(find.byTooltip('Search options'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<int>, 'Match case'),
      );
      await settle(tester);
      expect(find.text('No results'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);
      expect(find.text('No results'), findsOneWidget);
      await tester.tap(find.byTooltip('Close search'));
      await settle(tester);
      expect(find.byTooltip('Search'), findsOneWidget);

      // The system back gesture closes search before leaving.
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(find.byType(ReaderView), findsOneWidget);
    });

    testWidgets('long press selects; Copy puts the text on the clipboard', (
      tester,
    ) async {
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
      final origin = tester.getTopLeft(find.byType(ReaderView));
      final word = origin + charCentre(7);
      await tester.longPressAt(word);
      await settle(tester);
      expect(find.text('Copy'), findsOneWidget);
      // The bar floats next to the selected word, not at the bottom.
      final bar = tester.getRect(find.text('Copy'));
      expect((bar.center.dy - word.dy).abs(), lessThan(100));
      expect((bar.center.dx - word.dx).abs(), lessThan(150));
      await tester.tap(find.text('Copy'));
      await settle(tester);
      expect(copied.single, {'text': 'world'});
      expect(find.text('Text copied.'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('Dictionary looks the selection up (FR-TEXT-008)', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('doxa-reader-dict-');
      addTearDown(() => root.deleteSync(recursive: true));
      final library = DictionaryLibrary(root.path);
      await tester.runAsync(library.load);
      final lookup = _RecordingLookup();
      await show(
        tester,
        builder: (context, child) => DictionaryScope(
          library: library,
          lookup: lookup,
          openUri: (_) async => true,
          child: child!,
        ),
      );
      final origin = tester.getTopLeft(find.byType(ReaderView));
      await tester.longPressAt(origin + charCentre(7));
      await settle(tester);
      await tester.tap(find.text('Dictionary'));
      await settle(tester);
      // No dictionary is installed yet, so the popup explains how to get one.
      expect(find.text('Get dictionaries'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('dragging a handle extends; a tap clears', (tester) async {
      await show(tester);
      final origin = tester.getTopLeft(find.byType(ReaderView));
      await tester.longPressAt(origin + charCentre(1));
      await settle(tester);
      final view = tester.widget<ReaderView>(find.byType(ReaderView));
      final selection = view.selection!;
      expect(selection.text, 'hello');
      final (_, end) = selection.handles()!;
      await tester.dragFrom(
        origin + end + const Offset(0, 8),
        const Offset(60, 0),
      );
      await settle(tester);
      expect(selection.text, 'hello world');
      // The page did not scroll while the handle moved.
      expect(view.controller.offset, Offset.zero);
      await tester.tapAt(origin + const Offset(300, 500));
      await settle(tester);
      expect(selection.hasSelection, isFalse);
    });
  });
}

class _RecordingLookup implements DictionaryLookup {
  final queries = <String>[];

  @override
  Future<LookupResult> lookup(
    String query,
    List<InstalledDictionary> dictionaries,
  ) async {
    queries.add(query);
    return const LookupResult([]);
  }

  @override
  Future<void> close() async {}
}
