// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_pdf/src/doxa_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

double contrast(Color a, Color b) {
  final (hi, lo) = (a.computeLuminance(), b.computeLuminance());
  final light = hi > lo ? hi : lo;
  final dark = hi > lo ? lo : hi;
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    group('${brightness.name} theme (UX §5, §6)', () {
      final scheme = doxaTheme(
        seed: const Color(0xFF7048E8),
        brightness: brightness,
      ).colorScheme;

      test('text stays legible on the background and on cards', () {
        for (final ground in [
          scheme.surface,
          scheme.surfaceContainerLow,
          scheme.surfaceContainerHigh,
        ]) {
          expect(contrast(scheme.onSurface, ground), greaterThanOrEqualTo(4.5));
          expect(
            contrast(scheme.onSurfaceVariant, ground),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(
          contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('dynamic colour changes the accent, not the surfaces', () {
        final other = doxaTheme(
          seed: const Color(0xFF2BAE66),
          brightness: brightness,
        ).colorScheme;
        expect(other.primary, isNot(scheme.primary));
        expect(other.surface, scheme.surface);
        expect(other.surfaceContainerLow, scheme.surfaceContainerLow);
      });
    });
  }

  testWidgets('the interface font and its licence ship with the app', (
    tester,
  ) async {
    final theme = doxaTheme(
      seed: const Color(0xFF7048E8),
      brightness: Brightness.light,
    );
    expect(theme.textTheme.bodyMedium?.fontFamily, doxaFontFamily);
    registerFontLicenses();
    final entries = await tester.runAsync(
      () => LicenseRegistry.licenses.toList(),
    );
    final manrope = entries!.where((e) => e.packages.contains('Manrope'));
    expect(manrope, isNotEmpty);
    expect(
      manrope.first.paragraphs.map((p) => p.text).join(' '),
      contains('SIL OPEN FONT LICENSE'),
    );
  });
}
