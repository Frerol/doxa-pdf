// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_pdf/src/doxa_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shows the home in English', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const DoxaApp());

    expect(find.text('Doxa PDF'), findsOneWidget);
    // An empty library shows how to start (UX §5: no tabs on the home).
    expect(find.text('Documents you open appear here.'), findsOneWidget);
  });

  testWidgets('shows the home in Brazilian Portuguese', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const DoxaApp());

    expect(
      find.text('Os documentos que você abrir aparecem aqui.'),
      findsOneWidget,
    );
  });
}
