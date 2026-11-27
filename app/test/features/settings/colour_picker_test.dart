// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_pdf/features/settings/app_settings.dart';
import 'package:doxa_pdf/features/settings/colour_picker.dart';
import 'package:doxa_pdf/features/settings/settings_page.dart';
import 'package:doxa_pdf/l10n/gen/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showPage(WidgetTester tester, Widget body) async {
  tester.view
    ..physicalSize = const Size(340, 640)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: body),
    ),
  );
}

Future<void> openPicker(
  WidgetTester tester, {
  ValueChanged<Color?>? onResult,
}) async {
  await showPage(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final result = await showColourPicker(
            context,
            initial: const Color(0xFFA02030),
            title: 'Pick a colour',
          );
          onResult?.call(result);
        },
        child: const Text('Open picker'),
      ),
    ),
  );
  await tester.tap(find.text('Open picker'));
  await tester.pumpAndSettle();
}

void main() {
  final hexField = find.byType(TextField);
  final wheel = find.byKey(const ValueKey('colour-wheel'));
  final confirm = find.widgetWithText(TextButton, 'OK');

  String hex(WidgetTester tester) =>
      tester.widget<TextField>(hexField).controller!.text;

  group('FR-VIEW-016 / #128', () {
    testWidgets('valid hex updates brightness and returns the exact RGB', (
      tester,
    ) async {
      Color? result;
      await openPicker(tester, onResult: (colour) => result = colour);
      final initialValue = tester.widget<Slider>(find.byType(Slider)).value;

      await tester.enterText(hexField, '12aBcD');
      await tester.pumpAndSettle();
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        greaterThan(initialValue),
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(result, const Color(0xFF12ABCD));
    });

    testWidgets('invalid hex shows an error and disables confirmation', (
      tester,
    ) async {
      await openPicker(tester);

      await tester.enterText(hexField, '#12X456');
      await tester.pumpAndSettle();

      expect(find.text('Not a colour code'), findsOneWidget);
      expect(tester.widget<TextButton>(confirm).enabled, isFalse);

      await tester.enterText(hexField, '#123456');
      await tester.pumpAndSettle();

      expect(find.text('Not a colour code'), findsNothing);
      expect(tester.widget<TextButton>(confirm).enabled, isTrue);
    });

    testWidgets('wheel tap and drag and brightness update the hex code', (
      tester,
    ) async {
      await openPicker(tester);
      final initial = hex(tester);
      final center = tester.getCenter(wheel);
      await tester.tapAt(center + const Offset(0, 50));
      await tester.pumpAndSettle();

      final tapped = hex(tester);
      expect(tapped, isNot(initial));

      await tester.dragFrom(
        center + const Offset(0, 50),
        const Offset(50, -20),
      );
      await tester.pumpAndSettle();

      final dragged = hex(tester);
      expect(dragged, isNot(tapped));

      await tester.tapAt(tester.getCenter(find.byType(Slider)));
      await tester.pumpAndSettle();

      expect(hex(tester), isNot(dragged));
    });

    testWidgets('cancelling the custom background keeps the saved colour', (
      tester,
    ) async {
      final settings = SettingsController(MemorySettingsStore());
      addTearDown(settings.dispose);
      final initial = settings.value.customBackground;
      await showPage(tester, CustomColorsEditor(settings: settings));
      await tester.tap(find.bySemanticsLabel('Page colour: Custom colour'));
      await tester.pumpAndSettle();

      await tester.enterText(hexField, '#7289AB');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(settings.value.customBackground, initial);
    });

    testWidgets('custom swatches save the selected page and text colours', (
      tester,
    ) async {
      final store = MemorySettingsStore();
      final settings = SettingsController(store);
      addTearDown(settings.dispose);
      final initial = settings.value;
      await showPage(tester, CustomColorsEditor(settings: settings));

      final background = find.bySemanticsLabel('Page colour: Custom colour');
      await tester.tap(background);
      await tester.pumpAndSettle();
      await tester.enterText(hexField, '#7289AB');
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(settings.value.customBackground, const Color(0xFF7289AB));
      expect(settings.value.customText, initial.customText);
      expect(settings.value.colorMode, initial.colorMode);
      expect(
        tester
            .getSemantics(background)
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );

      await tester.tap(find.bySemanticsLabel('Text colour: Custom colour'));
      await tester.pumpAndSettle();
      await tester.enterText(hexField, '#AB8972');
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      await settings.flush();
      final saved = AppSettings.fromJson((await store.read())!);
      expect(saved.customBackground, const Color(0xFF7289AB));
      expect(saved.customText, const Color(0xFFAB8972));
    });
  });
}
