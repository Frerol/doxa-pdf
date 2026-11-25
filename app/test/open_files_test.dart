// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:collection';

import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/reader/reader_page.dart';
import 'package:doxa_pdf/features/reader/reader_view.dart';
import 'package:doxa_pdf/src/doxa_app.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

PlatformPdf pdf(int id, String name) => PlatformPdf(
  leaseId: id,
  uri: 'content://provider/$id',
  displayName: name,
  path: '/proc/self/fd/$id',
  persistedRead: true,
  persistedWrite: false,
);

class FakePdfDocuments implements PdfDocuments {
  final _signals = StreamController<void>.broadcast();
  Future<void> close() => _signals.close();
  void notifyIncoming() => _signals.add(null);
  final incoming = Queue<PlatformPdf>();
  final released = <int>[];
  PlatformPdf? picked;
  PdfAccessError? pickError;
  void Function()? onRelease;

  @override
  Stream<void> get incomingPdfs => _signals.stream;

  @override
  Future<PlatformPdf?> takeIncomingPdf() async =>
      incoming.isEmpty ? null : incoming.removeFirst();

  @override
  Future<PlatformPdf?> pickPdf() async {
    if (pickError case final error?) throw PdfAccessException(error);
    return picked;
  }

  @override
  Future<PlatformPdf> openPersistedPdf(String uri) =>
      throw UnimplementedError();

  @override
  Future<void> releasePdf(int leaseId) async {
    onRelease?.call();
    released.add(leaseId);
  }
}

void main() {
  late FakePdfDocuments documents;
  late FakePdfEngine engine;

  setUp(() {
    documents = FakePdfDocuments();
    engine = FakePdfEngine({
      pdf(1, 'Picked.pdf').path: const FakeDocument(pages: [FakePage()]),
      pdf(2, 'Locked.pdf').path: const FakeDocument(
        pages: [FakePage()],
        password: 'study',
      ),
      pdf(3, 'Shared.pdf').path: const FakeDocument(pages: [FakePage()]),
    });
    addTearDown(documents.close);
  });

  Future<void> launch(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      DoxaApp(engine: () async => engine, pdfDocuments: documents),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.text('Open file'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens the picker result and releases it after reader close', (
    tester,
  ) async {
    documents.picked = pdf(1, 'Provider name.pdf');
    documents.onRelease = () => expect(engine.openDocumentCount, 0);
    await launch(tester);
    await pick(tester);
    expect(find.text('Provider name.pdf'), findsOneWidget);
    expect(find.byType(ReaderView), findsOneWidget);
    expect(documents.released, isEmpty);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(documents.released, [1]);
  });

  testWidgets('cancelling the picker stays at home', (tester) async {
    await launch(tester);
    await pick(tester);
    expect(find.byType(ReaderPage), findsNothing);
    expect(find.text('Open file'), findsOneWidget);
  });

  testWidgets('handles a cold start and a subsequent incoming intent', (
    tester,
  ) async {
    documents.incoming.add(pdf(1, 'Cold start.pdf'));
    await launch(tester);
    expect(find.text('Cold start.pdf'), findsOneWidget);

    documents.incoming.add(pdf(3, 'Shared.pdf'));
    documents.notifyIncoming();
    await tester.pumpAndSettle();
    expect(find.text('Shared.pdf'), findsOneWidget);
    expect(engine.openDocumentCount, 2);
  });

  testWidgets('shows a wrong password and unlocks on retry', (tester) async {
    documents.picked = pdf(2, 'Locked.pdf');
    await launch(tester);
    await pick(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password. Try again.'), findsOneWidget);
    expect(documents.released, isEmpty);

    await tester.enterText(find.byType(TextField), 'study');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ReaderView), findsOneWidget);
  });

  testWidgets('cancelling the password prompt closes the reader', (
    tester,
  ) async {
    documents.picked = pdf(2, 'Locked.pdf');
    await launch(tester);
    await pick(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderPage), findsNothing);
    expect(documents.released, [2]);
  });

  const errors = {
    PdfAccessError.missing: 'The file was not found.',
    PdfAccessError.unreadable: 'The file could not be read.',
    PdfAccessError.notPdf: 'This file is not a valid PDF.',
    PdfAccessError.permissionLost:
        'Access to this file was lost. Open it again with the system picker.',
  };
  for (final MapEntry(:key, :value) in errors.entries) {
    testWidgets('reports ${key.name} with a localized message', (tester) async {
      documents.pickError = key;
      await launch(tester);
      await pick(tester);
      expect(find.text(value), findsOneWidget);
      expect(find.byType(ReaderPage), findsNothing);
    });
  }
}
