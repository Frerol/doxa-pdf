// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_pdf/src/doxa_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shows the placeholder home in English', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const DoxaApp());

    expect(find.text('Doxa PDF'), findsOneWidget);
    expect(find.text('A free PDF reader for studying'), findsOneWidget);
  });

  testWidgets('shows the placeholder home in Brazilian Portuguese', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const DoxaApp());

    expect(find.text('Um leitor de PDF livre para estudar'), findsOneWidget);
  });
}
