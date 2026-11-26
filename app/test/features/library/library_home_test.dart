// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/library/library_database.dart';
import 'package:doxa_pdf/features/library/library_home.dart';
import 'package:doxa_pdf/features/library/library_repository.dart';
import 'package:doxa_pdf/features/reader/reader_page.dart';
import 'package:doxa_pdf/l10n/gen/app_localizations.dart';
import 'package:doxa_pdf/src/doxa_app.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

PlatformPdf pdf(int id, String name, {bool persisted = true}) => PlatformPdf(
  leaseId: id,
  uri: 'content://provider/$id',
  displayName: name,
  path: '/proc/self/fd/$id',
  persistedRead: persisted,
  persistedWrite: false,
);

class FakePdfDocuments implements PdfDocuments {
  final _signals = StreamController<void>.broadcast();
  PlatformPdf? picked;
  final persisted = <String, PlatformPdf>{};
  PdfAccessError? reopenError;
  final released = <int>[];

  Future<void> close() => _signals.close();

  @override
  Stream<void> get incomingPdfs => _signals.stream;

  @override
  Future<PlatformPdf?> takeIncomingPdf() async => null;

  @override
  Future<PlatformPdf?> pickPdf() async => picked;

  @override
  Future<PlatformPdf> openPersistedPdf(String uri) async {
    if (reopenError case final error?) throw PdfAccessException(error);
    return persisted[uri] ??
        (throw const PdfAccessException(PdfAccessError.missing));
  }

  @override
  Future<void> releasePdf(int leaseId) async => released.add(leaseId);
}

void main() {
  late LibraryDatabase db;
  late LibraryRepository library;
  late FakePdfDocuments documents;
  late FakePdfEngine engine;
  final now = DateTime(2026, 11, 26, 10);

  setUp(() {
    db = LibraryDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    library = LibraryRepository(db, clock: () => now);
    documents = FakePdfDocuments();
    engine = FakePdfEngine({
      for (final id in [1, 2])
        pdf(id, '').path: FakeDocument(
          pages: List.filled(20, const FakePage(width: 400, height: 600)),
        ),
    });
  });
  tearDown(() async {
    await documents.close();
    await db.close();
  });

  Future<void> launch(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      DoxaApp(
        engine: () async => engine,
        pdfDocuments: documents,
        library: library,
        // One identity per path: the fake paths are not real files.
        identify: (path) async => 'id:$path',
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPicked(WidgetTester tester, PlatformPdf picked) async {
    documents.picked = picked;
    documents.persisted[picked.uri] = picked;
    await tester.tap(find.text('Open file'));
    await tester.pumpAndSettle();
  }

  Future<void> closeReader(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  group('recents (FR-FILE-004, FR-BOOK-002)', () {
    testWidgets('an opened document is listed with its progress', (
      tester,
    ) async {
      await launch(tester);
      expect(find.text('Documents you open appear here.'), findsOneWidget);
      await openPicked(tester, pdf(1, 'Calculus.pdf'));
      await closeReader(tester);
      expect(find.text('Calculus.pdf'), findsOneWidget);
      // Closing the reader saved the page count and the position.
      expect(find.textContaining('p. 1 of 20'), findsOneWidget);
      expect(find.textContaining('today'), findsOneWidget);
    });

    testWidgets('removing a document hides it from recents only', (
      tester,
    ) async {
      await launch(tester);
      await openPicked(tester, pdf(1, 'Calculus.pdf'));
      await closeReader(tester);
      await tester.tap(find.byTooltip('Add to favorites'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from recents'));
      await tester.pumpAndSettle();
      expect(find.text('Calculus.pdf'), findsNothing);

      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.text('Calculus.pdf'), findsOneWidget);
    });

    testWidgets('the name filter ignores case and accents', (tester) async {
      await launch(tester);
      await openPicked(tester, pdf(1, 'Cálculo.pdf'));
      await closeReader(tester);
      await openPicked(tester, pdf(2, 'Physics.pdf'));
      await closeReader(tester);

      await tester.tap(find.byTooltip('Search by name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'CALC');
      await tester.pumpAndSettle();
      expect(find.text('Cálculo.pdf'), findsOneWidget);
      expect(find.text('Physics.pdf'), findsNothing);
    });
  });

  group('reopening (FR-VIEW-006)', () {
    testWidgets('restores the saved page, zoom and page order', (tester) async {
      final opened = pdf(1, 'Calculus.pdf');
      documents.persisted[opened.uri] = opened;
      final doc = await library.recordOpen(
        identity: 'id:${opened.path}',
        displayName: opened.displayName,
        uri: opened.uri,
      );
      const saved = (page: 12, x: 0.0, y: 0.25, zoom: 1.5, rightToLeft: true);
      await library.saveState(doc.id, saved, pageCount: 20);

      await launch(tester);
      await tester.tap(find.text('Calculus.pdf'));
      await tester.pumpAndSettle();
      final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
      expect(reader.initialPosition, (page: 12, x: 0.0, y: 0.25, zoom: 1.5));
      expect(reader.initialRightToLeft, isTrue);
      await closeReader(tester);
      expect(documents.released, [1]);
    });

    testWidgets('a lost permission explains how to open the file again', (
      tester,
    ) async {
      await launch(tester);
      await openPicked(tester, pdf(1, 'Calculus.pdf'));
      await closeReader(tester);
      documents.reopenError = PdfAccessError.permissionLost;

      await tester.tap(find.text('Calculus.pdf'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage), findsNothing);
      expect(
        find.text(
          'This document can no longer be opened from here. '
          'Open it again with Open file.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a file shared without a lasting grant is not reopened', (
      tester,
    ) async {
      await launch(tester);
      await openPicked(tester, pdf(1, 'Shared.pdf', persisted: false));
      await closeReader(tester);

      await tester.tap(find.text('Shared.pdf'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage), findsNothing);
      expect(find.textContaining('no longer be opened'), findsOneWidget);
    });
  });

  group('last read label (FR-BOOK-002)', () {
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('counts calendar days, not 24-hour periods', () {
      final morning = DateTime(2026, 11, 26, 8);
      expect(lastReadLabel(l10n, DateTime(2026, 11, 26, 7), morning), 'today');
      expect(
        lastReadLabel(l10n, DateTime(2026, 11, 25, 23, 50), morning),
        'yesterday',
      );
      expect(
        lastReadLabel(l10n, DateTime(2026, 11, 23, 9), morning),
        '3 days ago',
      );
    });

    test('shows a date from a week on', () {
      final label = lastReadLabel(
        l10n,
        DateTime(2026, 11, 2),
        DateTime(2026, 11, 26),
      );
      expect(label, contains('2026'));
    });
  });
}
