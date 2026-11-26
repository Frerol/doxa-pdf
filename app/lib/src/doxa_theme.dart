// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The one font family of the interface (docs/plan/05-ux-design.md §5):
/// Manrope, bundled as a variable font under the SIL OFL 1.1. PDF pages
/// keep their own fonts.
const doxaFontFamily = 'Manrope';

/// Neutral surfaces of the Doxa look (UX §5), the same with or without
/// dynamic colour: only the accent follows the wallpaper.
@immutable
final class DoxaSurfaces {
  const DoxaSurfaces._({
    required this.background,
    required this.card,
    required this.raised,
    required this.high,
    required this.highest,
    required this.deepest,
    required this.text,
    required this.secondaryText,
    required this.line,
  });

  static const light = DoxaSurfaces._(
    background: Color(0xFFF5F6FA),
    card: Color(0xFFFFFFFF),
    raised: Color(0xFFEEF0F5),
    high: Color(0xFFE8EAF0),
    highest: Color(0xFFE3E5EC),
    deepest: Color(0xFFFFFFFF),
    text: Color(0xFF161A23),
    secondaryText: Color(0xFF5A6070),
    line: Color(0xFFDDE0E8),
  );

  static const dark = DoxaSurfaces._(
    background: Color(0xFF161A23),
    card: Color(0xFF1E2330),
    raised: Color(0xFF1E2330),
    high: Color(0xFF262C3A),
    highest: Color(0xFF2E3548),
    deepest: Color(0xFF10131A),
    text: Color(0xFFE6E8EF),
    secondaryText: Color(0xFF9AA3B5),
    line: Color(0xFF262C3A),
  );

  /// The screen's background.
  final Color background;

  /// Cards and list rows on [background].
  final Color card;
  final Color raised;
  final Color high;
  final Color highest;

  /// Behind the PDF page in the reader.
  final Color deepest;
  final Color text;
  final Color secondaryText;
  final Color line;
}

/// The app's theme for [brightness], with [seed] as the accent (the Doxa
/// purple, or the wallpaper's colour with dynamic colour on, FR-SET-001).
ThemeData doxaTheme({required Color seed, required Brightness brightness}) {
  final s = brightness == Brightness.dark
      ? DoxaSurfaces.dark
      : DoxaSurfaces.light;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
      .copyWith(
        surface: s.background,
        onSurface: s.text,
        onSurfaceVariant: s.secondaryText,
        surfaceContainerLowest: s.deepest,
        surfaceContainerLow: s.card,
        surfaceContainer: s.raised,
        surfaceContainerHigh: s.high,
        surfaceContainerHighest: s.highest,
        outlineVariant: s.line,
      );
  final base = ThemeData(
    colorScheme: scheme,
    fontFamily: doxaFontFamily,
    scaffoldBackgroundColor: s.background,
  );
  final text = base.textTheme;
  const medium = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(14)),
  );
  return base.copyWith(
    // Headings are heavy and slightly tight, as in the chosen design.
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: s.background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge?.copyWith(
        color: s.text,
        fontWeight: FontWeight.w800,
      ),
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: s.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    listTileTheme: const ListTileThemeData(shape: medium),
    filledButtonTheme: const FilledButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(medium)),
    ),
    outlinedButtonTheme: const OutlinedButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(medium)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: s.text,
      foregroundColor: s.background,
      shape: medium,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.card,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide.none,
      ),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: medium,
    ),
    dividerTheme: DividerThemeData(color: s.line, space: 1),
  );
}

/// Shows Manrope's licence on the licences page (#55).
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/Manrope-OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Manrope'], text);
  });
}
