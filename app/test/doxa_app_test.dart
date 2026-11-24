// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_pdf/src/doxa_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<EngineCheckResult> _fakeCheck() async => EngineCheckResult(
  pageCount: 1,
  pageWidth: 200,
  pageHeight: 200,
  text: 'Hello Doxa',
  bgraPixels: Uint8List(2 * 2 * 4),
  renderWidth: 2,
  renderHeight: 2,
  elapsed: const Duration(milliseconds: 12),
);

Future<EngineCheckResult> _failingCheck() async =>
    throw StateError('library missing');

void main() {
  testWidgets('shows the placeholder home in English', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const DoxaApp(engineCheck: _fakeCheck));

    expect(find.text('Doxa PDF'), findsOneWidget);
    expect(find.text('A free PDF reader for studying'), findsOneWidget);
    expect(find.text('PDF engine check'), findsOneWidget);
  });

  testWidgets('shows the placeholder home in Brazilian Portuguese', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const DoxaApp(engineCheck: _fakeCheck));

    expect(find.text('Um leitor de PDF livre para estudar'), findsOneWidget);
    expect(find.text('Verificação do motor PDF'), findsOneWidget);
  });

  testWidgets('engine check shows the result and the rendered page', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const DoxaApp(engineCheck: _fakeCheck));

    await tester.runAsync(() async {
      await tester.tap(find.text('Run check'));
      // Let the image decode on the engine side.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(
      find.text('PDFium OK: 1 page(s), 200 × 200 pt, text “Hello Doxa”, 12 ms'),
      findsOneWidget,
    );
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('engine check reports failures', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const DoxaApp(engineCheck: _failingCheck));

    await tester.tap(find.text('Run check'));
    await tester.pump();

    expect(
      find.text('PDFium failed: Bad state: library missing'),
      findsOneWidget,
    );
  });
}
