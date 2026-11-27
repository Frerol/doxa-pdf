// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/reader/color_mode.dart';
import 'package:doxa_pdf/features/reader/reader_geometry.dart';
import 'package:doxa_pdf/features/reader/reader_page.dart';
import 'package:doxa_pdf/features/reader/reader_view.dart';
import 'package:doxa_pdf/features/reader/view_options.dart';
import 'package:doxa_pdf/features/settings/app_settings.dart';
import 'package:doxa_pdf/features/settings/settings_page.dart';
import 'package:doxa_pdf/l10n/gen/app_localizations.dart';
import 'package:doxa_pdf/src/doxa_app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../reader/test_images.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  group('page colour filters (FR-VIEW-005, FR-VIEW-016)', () {
    const white = Color(0xFFFFFFFF), black = Color(0xFF000000);

    test('night swaps white and black and keeps hues', () {
      expect(applyColorMatrix(nightMatrix, white), black);
      expect(applyColorMatrix(nightMatrix, black), white);
      // A dark red stays red-ish (red is its largest channel).
      final red = applyColorMatrix(nightMatrix, const Color(0xFF800000));
      expect(red.r, greaterThan(red.g));
      expect(red.r, greaterThan(red.b));
    });

    test('normal has no filter; the others do', () {
      expect(pageColorFilter(PageColorMode.normal), isNull);
      for (final mode in [
        PageColorMode.night,
        PageColorMode.sepia,
        PageColorMode.custom,
      ]) {
        expect(pageColorFilter(mode), isNotNull, reason: mode.name);
      }
    });

    test('blank sheets match the mode', () {
      expect(sheetColor(PageColorMode.normal), white);
      expect(sheetColor(PageColorMode.night), black);
      expect(sheetColor(PageColorMode.sepia), sepiaPaper);
      expect(
        sheetColor(PageColorMode.custom, background: const Color(0xFF123456)),
        const Color(0xFF123456),
      );
    });
  });

  group('AppSettings', () {
    test('round-trips through JSON', () {
      const settings = AppSettings(
        themeMode: ThemeMode.dark,
        dynamicColor: false,
        languageCode: 'pt',
        colorMode: PageColorMode.custom,
        customBackground: Color(0xFF101010),
        customText: Color(0xFFEEEEEE),
        keepScreenOn: true,
        readerMode: ReaderMode.twoPages,
        coverPage: false,
        tapZones: false,
        keepZoomOnTurn: true,
      );
      final copy = AppSettings.fromJson(settings.toJson());
      expect(copy.toJson(), settings.toJson());
    });

    test('ignores broken and unknown values', () {
      final settings = AppSettings.fromJson({
        'themeMode': 'purple',
        'dynamicColor': 'yes',
        'languageCode': 'xx',
        'colorMode': 3,
        'keepScreenOn': true,
        'readerMode': 'unknown',
        'coverPage': 'false',
        'tapZones': 1,
        'keepZoomOnTurn': 'true',
      });
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.dynamicColor, isTrue);
      expect(settings.languageCode, isNull);
      expect(settings.colorMode, PageColorMode.normal);
      expect(settings.keepScreenOn, isTrue);
      for (final value in [settings, AppSettings.fromJson({})]) {
        const defaults = ReaderOptions();
        expect(value.readerMode, defaults.mode);
        expect(value.coverPage, defaults.coverPage);
        expect(value.tapZones, defaults.tapZones);
        expect(value.keepZoomOnTurn, defaults.keepZoomOnTurn);
      }
    });

    test('a file store saves atomically and survives a damaged file', () async {
      final dir = await Directory.systemTemp.createTemp('doxa-settings-');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileSettingsStore(Future.value(dir.path));
      expect(await store.read(), isNull);
      final controller = SettingsController(store);
      controller.update(controller.value.copyWith(themeMode: ThemeMode.dark));
      controller.update(controller.value.copyWith(keepScreenOn: true));
      await controller.flush();
      final again = SettingsController(store);
      await again.load();
      expect(again.value.themeMode, ThemeMode.dark);
      expect(again.value.keepScreenOn, isTrue);
      expect(File('${dir.path}/settings.json.tmp').existsSync(), isFalse);

      File('${dir.path}/settings.json').writeAsStringSync('{not json');
      final damaged = SettingsController(store);
      await damaged.load();
      expect(damaged.value.themeMode, ThemeMode.system);
    });
  });

  testWidgets('the support search result opens the Doxa Ko-fi page (#125)', (
    tester,
  ) async {
    final requestedUris = <String>[];
    await tester.pumpWidget(
      DoxaApp(
        settings: SettingsController(MemorySettingsStore()),
        openUri: (uri) async {
          requestedUris.add(uri);
          return true;
        },
      ),
    );

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'Ko-fi');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support Doxa'));

    expect(requestedUris, ['https://ko-fi.com/P2S82BD7LL']);
  });

  group('app and settings screen (FR-SET-001, FR-SET-002)', () {
    testWidgets('theme, language and dynamic colour apply at once', (
      tester,
    ) async {
      final settings = SettingsController(MemorySettingsStore());
      await tester.pumpWidget(
        DoxaApp(
          settings: settings,
          accentColor: () async => const Color(0xFF00AA55),
        ),
      );
      MaterialApp app() => tester.widget(find.byType(MaterialApp));
      expect(app().themeMode, ThemeMode.system);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(app().themeMode, ThemeMode.dark);
      expect(settings.value.themeMode, ThemeMode.dark);

      final dynamicSeed = app().theme!.colorScheme.primary;
      await tester.tap(find.text('Colours from the wallpaper'));
      await tester.pumpAndSettle();
      expect(app().theme!.colorScheme.primary, isNot(dynamicSeed));

      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Português (Brasil)'));
      await tester.pumpAndSettle();
      expect(app().locale, const Locale('pt'));
      expect(find.text('Geral'), findsOneWidget);

      await tester.tap(find.text('Idioma'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Idioma do sistema'));
      await tester.pumpAndSettle();
      expect(app().locale, isNull);
    });

    testWidgets('custom page colours offer swatches', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = SettingsController(MemorySettingsStore());
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: SettingsPage(settings: settings),
        ),
      );
      await tester.tap(find.text('Viewing'));
      await tester.pumpAndSettle();
      expect(find.text('Page colour'), findsNothing);
      await tester.tap(find.text('Page colours for new documents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(find.text('Page colour'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Page colour 2'));
      await tester.pumpAndSettle();
      expect(settings.value.customBackground, customBackgrounds[1]);
    });

    Future<SettingsController> showSettings(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
    }) async {
      tester.view
        ..physicalSize = const Size(800, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = SettingsController(MemorySettingsStore());
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: SettingsPage(settings: settings),
        ),
      );
      await tester.pumpAndSettle();
      return settings;
    }

    testWidgets('each category lists its settings (UX §7)', (tester) async {
      final settings = await showSettings(tester);
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Language'), findsWidgets);
      expect(find.text('Tap the edges to turn pages'), findsNothing);
      await tester.tap(find.text('Keep the screen on while reading'));
      await tester.pumpAndSettle();
      expect(settings.value.keepScreenOn, isTrue);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Viewing'));
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsNothing);
      final keepZoom = settings.value.keepZoomOnTurn;
      await tester.tap(find.text('Keep zoom when turning pages'));
      await tester.pumpAndSettle();
      expect(settings.value.keepZoomOnTurn, !keepZoom);
    });

    testWidgets('search finds settings by title or description, ignoring '
        'case and accents (UX §7)', (tester) async {
      final settings = await showSettings(tester, locale: const Locale('pt'));
      // A word of a description, typed without its accent and in capitals.
      await tester.enterText(find.byType(SearchBar), 'NAO APAGA');
      await tester.pumpAndSettle();
      expect(
        find.text('Manter a tela acesa durante a leitura'),
        findsOneWidget,
      );
      expect(find.text('Tema'), findsNothing);
      // A result works in place.
      await tester.tap(find.text('Manter a tela acesa durante a leitura'));
      await tester.pumpAndSettle();
      expect(settings.value.keepScreenOn, isTrue);

      await tester.enterText(find.byType(SearchBar), 'zoom');
      await tester.pumpAndSettle();
      expect(find.text('Visualização'), findsOneWidget);
      expect(find.text('Manter a tela acesa durante a leitura'), findsNothing);

      await tester.enterText(find.byType(SearchBar), 'xyzzy');
      await tester.pumpAndSettle();
      expect(find.textContaining('xyzzy'), findsWidgets);
      expect(find.byType(SwitchListTile), findsNothing);

      // Clearing the search brings the categories back.
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text('Geral'), findsOneWidget);
    });
  });

  group('reader comfort', () {
    late List<bool> screenOn;

    Future<void> show(
      WidgetTester tester,
      AppSettings settings, {
      SettingsController? controller,
      String path = 'doc.pdf',
    }) async {
      tester.view
        ..physicalSize = const Size(800, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      screenOn = [];
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
            key: ValueKey(path),
            engine: Future.value(
              FakePdfEngine({
                path: FakeDocument(pages: List.filled(3, const FakePage())),
              }),
            ),
            source: FileSource(path),
            title: path,
            decoder: decoder.call,
            settings:
                controller ??
                (SettingsController(MemorySettingsStore())..value = settings),
            keepScreenOn: (on) async => screenOn.add(on),
          ),
        ),
      );
      await settle(tester);
    }

    ReaderView view(WidgetTester tester) =>
        tester.widget<ReaderView>(find.byType(ReaderView));

    testWidgets('opens with the default colours and switches at once', (
      tester,
    ) async {
      final store = MemorySettingsStore();
      final settings = SettingsController(store)
        ..value = const AppSettings(colorMode: PageColorMode.sepia);
      await show(tester, settings.value, controller: settings);
      final reader = view(tester).controller
        ..goToPage(1)
        ..zoomTo(2);
      final page = reader.currentPage;
      expect(page, 1);
      expect(view(tester).sheetColor, sepiaPaper);
      expect(view(tester).colorFilter, isNotNull);
      await tester.tap(find.byTooltip('View options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Normal'));
      await tester.pumpAndSettle();
      expect(view(tester).colorFilter, isNull);
      await tester.tap(find.text('Night'));
      await tester.pumpAndSettle();
      expect(view(tester).sheetColor, const Color(0xFF000000));
      await settings.flush();
      expect(settings.value.colorMode, PageColorMode.night);
      expect(store.json?['colorMode'], 'night');

      settings.update(settings.value.copyWith(colorMode: PageColorMode.sepia));
      await tester.pumpAndSettle();
      expect(view(tester).sheetColor, sepiaPaper);
      expect(reader.currentPage, page);
      expect(reader.zoom, 2);
    });

    testWidgets('view options saves layout defaults for another document', (
      tester,
    ) async {
      final store = MemorySettingsStore();
      final settings = SettingsController(store);
      await show(tester, settings.value, controller: settings);
      final reader = view(tester).controller..goToPage(1);

      await tester.tap(find.byTooltip('View options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Single page'));
      await tester.pumpAndSettle();
      expect(reader.currentPage, 1);

      await tester.tap(find.text('Two pages'));
      await tester.pumpAndSettle();
      for (final label in [
        'Tap the edges to turn pages',
        'Keep zoom when turning pages',
      ]) {
        final tile = find.widgetWithText(SwitchListTile, label);
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }
      // Each choice applied behind the dialog, which is still open (#110).
      expect(find.byType(ViewOptionsDialog), findsOneWidget);
      await settings.flush();
      expect(
        reader.options,
        const ReaderOptions(
          mode: ReaderMode.twoPages,
          coverPage: false,
          tapZones: false,
          keepZoomOnTurn: false,
        ),
      );
      final saved = store.json;
      expect(saved, containsPair('readerMode', 'twoPages'));
      expect(saved, containsPair('coverPage', false));
      expect(saved, containsPair('tapZones', false));
      expect(saved, containsPair('keepZoomOnTurn', false));

      final rightToLeft = find.widgetWithText(
        SwitchListTile,
        'Right-to-left pages',
      );
      await tester.ensureVisible(rightToLeft);
      await tester.tap(rightToLeft);
      await tester.pumpAndSettle();
      expect(reader.options.rightToLeft, isTrue);
      await settings.flush();
      expect(store.json, same(saved));
      expect(store.json, isNot(contains('rightToLeft')));
      // A tap outside closes it, like OK (maintainer, tablet check).
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(ViewOptionsDialog), findsNothing);

      await show(
        tester,
        settings.value,
        controller: settings,
        path: 'other.pdf',
      );
      expect(
        view(tester).controller.options,
        const ReaderOptions(
          mode: ReaderMode.twoPages,
          coverPage: false,
          tapZones: false,
          keepZoomOnTurn: false,
        ),
      );
      expect(view(tester).controller.layout, isA<StripLayout>());
    });

    testWidgets('layout tiles and the scrolling choice work together (#110)', (
      tester,
    ) async {
      final settings = SettingsController(MemorySettingsStore());
      await show(tester, settings.value, controller: settings);
      final reader = view(tester).controller;
      expect(reader.options.mode, ReaderMode.continuous);
      await tester.tap(find.byTooltip('View options'));
      await tester.pumpAndSettle();
      bool chosen(String label) => tester
          .widget<SegmentedButton<ViewScrolling>>(
            find.byType(SegmentedButton<ViewScrolling>),
          )
          .selected
          .contains(switch (label) {
            'Vertical' => ViewScrolling.vertical,
            'Horizontal' => ViewScrolling.horizontal,
            _ => ViewScrolling.paged,
          });
      expect(chosen('Vertical'), isTrue);

      // Page by page: the single page turns sideways.
      await tester.tap(find.text('Page by page'));
      await tester.pumpAndSettle();
      expect(reader.options.mode, ReaderMode.singlePage);
      expect(reader.layout!.paged, isTrue);

      // Horizontal scrolling: pages side by side, scrolled freely.
      await tester.tap(find.text('Horizontal'));
      await tester.pumpAndSettle();
      expect(reader.options.mode, ReaderMode.horizontal);
      expect(reader.layout, isA<StripLayout>());
      expect(reader.layout!.paged, isFalse);

      // Two-page layouts always turn page by page; the cover tile keeps
      // the first page alone.
      await tester.tap(find.text('Cover + two pages'));
      await tester.pumpAndSettle();
      expect(reader.options.mode, ReaderMode.twoPages);
      expect(reader.options.coverPage, isTrue);
      expect(reader.layout!.pagesOf(0), [0]);
      expect(chosen('Page by page'), isTrue);
      await tester.tap(find.text('Two pages'));
      await tester.pumpAndSettle();
      expect(reader.options.coverPage, isFalse);
      expect(reader.layout!.pagesOf(0), [0, 1]);

      // Vertical again: back to one page, scrolled up and down.
      await tester.tap(find.text('Vertical'));
      await tester.pumpAndSettle();
      expect(reader.options.mode, ReaderMode.continuous);
      expect(reader.layout, isA<ContinuousLayout>());

      // The layout tiles share one size, as small as their content.
      final sizes = {
        for (final label in ['Single page', 'Two pages', 'Cover + two pages'])
          tester.getSize(
            find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
          ),
      };
      expect(sizes, hasLength(1));
      // As wide as the longest label and the tile's padding, no wider.
      final longest = tester.getSize(find.text('Cover + two pages')).width;
      expect(sizes.single.width, closeTo(longest + 24, 1));
    });

    testWidgets('custom colours can be picked in the view options', (
      tester,
    ) async {
      await show(tester, const AppSettings(colorMode: PageColorMode.custom));
      await tester.tap(find.byTooltip('View options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Page colour 2'));
      await tester.pumpAndSettle();
      expect(view(tester).sheetColor, customBackgrounds[1]);
      // A paper and text combination sets both at once (#110).
      await tester.tap(find.bySemanticsLabel('Colours 4'));
      await tester.pumpAndSettle();
      expect(view(tester).sheetColor, customBackgrounds[3]);
    });

    testWidgets('full screen hides the bars; a tap brings them back', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await show(tester, const AppSettings());
      await tester.tap(find.byTooltip('View options'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Full screen'));
      await tester.tap(find.text('Full screen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(
        calls.map((c) => c.method),
        contains('SystemChrome.setEnabledSystemUIMode'),
      );
      await tester.tapAt(const Offset(400, 600));
      await settle(tester);
      expect(find.byType(AppBar), findsOneWidget);
      await tester.tapAt(const Offset(400, 600));
      await settle(tester);
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('keeps the screen on while open (FR-VIEW-013)', (tester) async {
      await show(tester, const AppSettings(keepScreenOn: true));
      expect(screenOn, [true]);
      await tester.pumpWidget(const SizedBox());
      expect(screenOn, [true, false]);
    });

    testWidgets('follows the setting while the document is open', (
      tester,
    ) async {
      await show(tester, const AppSettings());
      final page = tester.widget<ReaderPage>(find.byType(ReaderPage));
      page.settings!.update(const AppSettings(keepScreenOn: true));
      expect(screenOn, [true]);
      page.settings!.update(const AppSettings());
      expect(screenOn, [true, false]);
    });

    testWidgets('full screen keeps the page size when bars toggle', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await show(tester, const AppSettings());
      await tester.tap(find.byTooltip('View options'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Full screen'));
      await tester.tap(find.text('Full screen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(ReaderView));
      await tester.tapAt(const Offset(400, 600));
      await settle(tester);
      expect(find.byType(AppBar), findsOneWidget);
      expect(tester.getSize(find.byType(ReaderView)), size);
    });

    testWidgets('does nothing when the setting is off', (tester) async {
      await show(tester, const AppSettings());
      await tester.pumpWidget(const SizedBox());
      expect(screenOn, isEmpty);
    });
  });
}
