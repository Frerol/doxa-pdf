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

class FakeLibraryFolders implements LibraryFolders {
  PlatformFolder? picked;
  final listings = <String?, List<PlatformFolderEntry>>{};
  PdfAccessError? listError;
  final released = <String>[];

  @override
  Future<PlatformFolder?> pickFolder() async => picked;

  @override
  Future<List<PlatformFolderEntry>> listFolder(
    String treeUri, {
    String? documentId,
  }) async {
    if (listError case final error?) throw PdfAccessException(error);
    return listings[documentId] ?? const [];
  }

  @override
  Future<void> releaseFolder(String treeUri) async => released.add(treeUri);
}

class FakeDocumentFiles implements DocumentFiles {
  final calls = <String>[];
  DocumentFileError? error;

  /// Whether the provider leaves a lasting grant on renamed files.
  bool persists = true;

  /// URIs whose actions fail with [DocumentFileError.failed].
  final failing = <String>{};

  void _check([String? uri]) {
    if (error case final error?) throw DocumentFileException(error);
    if (failing.contains(uri)) {
      throw const DocumentFileException(DocumentFileError.failed);
    }
  }

  @override
  Future<PlatformMovedDocument> rename(String uri, String displayName) async {
    calls.add('rename $uri $displayName');
    _check();
    return PlatformMovedDocument(
      uri: '$uri-renamed',
      displayName: displayName,
      persisted: persists,
    );
  }

  @override
  Future<PlatformMovedDocument> move(
    String uri, {
    required String targetTreeUri,
    String? targetDocumentId,
  }) async {
    calls.add('move $uri $targetTreeUri $targetDocumentId');
    _check(uri);
    final name = uri.split('/').last;
    return PlatformMovedDocument(
      uri: '$targetTreeUri/document/$targetDocumentId%2F$name',
      displayName: name,
      persisted: true,
    );
  }

  @override
  Future<void> delete(String uri) async {
    calls.add('delete $uri');
    _check(uri);
  }
}

const tree = 'content://storage/tree/books';

PlatformFolderEntry folderEntry(String id, String name, {bool dir = false}) =>
    PlatformFolderEntry(
      documentId: id,
      uri: '$tree/document/$id',
      name: name,
      isDirectory: dir,
      size: dir ? null : 2400000,
      lastModified: DateTime(2026, 11, 20).millisecondsSinceEpoch,
    );

void main() {
  late LibraryDatabase db;
  late LibraryRepository library;
  late FakePdfDocuments documents;
  late FakePdfEngine engine;
  late FakeLibraryFolders folders;
  late FakeDocumentFiles files;
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
    folders = FakeLibraryFolders();
    files = FakeDocumentFiles();
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
        libraryFolders: folders,
        documentFiles: files,
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

  group('library folders (FR-FILE-006)', () {
    Future<void> addBooksFolder(WidgetTester tester) async {
      folders.picked = PlatformFolder(treeUri: tree, displayName: 'Books');
      await tester.tap(find.text('Folders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add folder'));
      await tester.pumpAndSettle();
    }

    testWidgets('an added folder is browsed level by level', (tester) async {
      final inside = pdf(2, 'Algebra.pdf');
      folders.listings[null] = [
        folderEntry('calc', 'Calculus.pdf'),
        folderEntry('sem', 'Semester 1', dir: true),
        folderEntry('img', 'Notes.pdf'),
      ];
      folders.listings['sem'] = [folderEntry('alg', 'Algebra.pdf')];
      documents.persisted['$tree/document/alg'] = inside;

      await launch(tester);
      await addBooksFolder(tester);
      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      // Folders first, then PDFs by name.
      final titles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.title! as Text).data)
          .toList();
      expect(titles, ['Semester 1', 'Calculus.pdf', 'Notes.pdf']);
      expect(find.textContaining('2.4 MB'), findsWidgets);

      await tester.tap(find.text('Semester 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Algebra.pdf'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage), findsOneWidget);
      await closeReader(tester);

      // Opened through the folder, the document is in recents and keeps
      // the folder's document URI for reopening.
      final recents = await tester.runAsync(() => library.watchRecents().first);
      expect(recents!.single.displayName, 'Algebra.pdf');
      expect(recents.single.uri, inside.uri);
    });

    testWidgets('the name filter narrows a folder', (tester) async {
      folders.listings[null] = [
        folderEntry('calc', 'Cálculo.pdf'),
        folderEntry('phys', 'Physics.pdf'),
      ];
      await launch(tester);
      await addBooksFolder(tester);
      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search by name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'calc');
      await tester.pumpAndSettle();
      expect(find.text('Cálculo.pdf'), findsOneWidget);
      expect(find.text('Physics.pdf'), findsNothing);
    });

    testWidgets('a lost grant explains what to do', (tester) async {
      folders.listError = PdfAccessError.permissionLost;
      await launch(tester);
      await addBooksFolder(tester);
      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Access to this folder was lost'),
        findsOneWidget,
      );
    });

    testWidgets('removing a folder releases its grant', (tester) async {
      await launch(tester);
      await addBooksFolder(tester);
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from library'));
      await tester.pumpAndSettle();
      expect(find.text('Books'), findsNothing);
      expect(folders.released, [tree]);
    });
  });

  group('rename, move and delete (FR-FILE-011)', () {
    Future<void> menu(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('Show menu').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('renaming keeps the extension and the reading state', (
      tester,
    ) async {
      await launch(tester);
      await openPicked(tester, pdf(1, 'Calculus.pdf'));
      await closeReader(tester);
      await menu(tester, 'Rename');
      await tester.enterText(find.byType(TextField), 'Calculus II');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(files.calls, ['rename content://provider/1 Calculus II.pdf']);
      expect(find.text('Calculus II.pdf'), findsOneWidget);
      expect(find.textContaining('p. 1 of 20'), findsOneWidget);
      final doc = (await tester.runAsync(() => library.watchRecents().first))!;
      expect(doc.single.uri, 'content://provider/1-renamed');
    });

    testWidgets('a rename that loses access says how to reopen', (
      tester,
    ) async {
      files.persists = false;
      await launch(tester);
      await openPicked(tester, pdf(1, 'Calculus.pdf'));
      await closeReader(tester);
      await menu(tester, 'Rename');
      await tester.enterText(find.byType(TextField), 'B');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('open it once with Open file'),
        findsOneWidget,
      );
      final doc = (await tester.runAsync(() => library.watchRecents().first))!;
      expect(doc.single.canReopen, isFalse);
    });

    testWidgets('deleting asks first, then leaves the library', (tester) async {
      await launch(tester);
      await openPicked(tester, pdf(1, 'Calculus.pdf'));
      await closeReader(tester);
      await menu(tester, 'Delete');
      expect(find.text('Delete “Calculus.pdf”?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(files.calls, isEmpty);
      expect(find.text('Calculus.pdf'), findsOneWidget);

      await menu(tester, 'Delete');
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(files.calls, ['delete content://provider/1']);
      expect(find.text('Calculus.pdf'), findsNothing);
    });

    testWidgets('a refused delete keeps the document and says why', (
      tester,
    ) async {
      files.error = DocumentFileError.unsupported;
      await launch(tester);
      await openPicked(tester, pdf(1, 'Calculus.pdf'));
      await closeReader(tester);
      await menu(tester, 'Delete');
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(
        find.text('This storage does not allow that for this file.'),
        findsOneWidget,
      );
      expect(find.text('Calculus.pdf'), findsOneWidget);
    });

    testWidgets('a file opened outside a library folder cannot be moved', (
      tester,
    ) async {
      await launch(tester);
      await openPicked(tester, pdf(1, 'Calculus.pdf'));
      await closeReader(tester);
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Move'), findsNothing);
    });

    testWidgets('a folder PDF moves into a subfolder picked level by level', (
      tester,
    ) async {
      // Opened through the folder, the document keeps its folder URI.
      final calc = PlatformPdf(
        leaseId: 2,
        uri: '$tree/document/calc',
        displayName: 'Calculus.pdf',
        path: pdf(2, '').path,
        persistedRead: true,
        persistedWrite: true,
      );
      folders.listings[null] = [
        folderEntry('calc', 'Calculus.pdf'),
        folderEntry('sem', 'Semester 1', dir: true),
      ];
      folders.listings['sem'] = [folderEntry('w1', 'Week 1', dir: true)];
      documents.persisted['$tree/document/calc'] = calc;

      await launch(tester);
      folders.picked = PlatformFolder(treeUri: tree, displayName: 'Books');
      await tester.tap(find.text('Folders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      // Open it once, so it is in recents.
      await tester.tap(find.text('Calculus.pdf'));
      await tester.pumpAndSettle();
      await closeReader(tester);

      await menu(tester, 'Move');
      // The library folders are read from the database first.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('Move to'), findsOneWidget);
      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semester 1'));
      await tester.pumpAndSettle();
      expect(find.text('Week 1'), findsOneWidget);
      // Back goes up one level, not out of the picker.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Semester 1'), findsOneWidget);
      await tester.tap(find.text('Semester 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move here'));
      await tester.pumpAndSettle();

      expect(files.calls, ['move $tree/document/calc $tree sem']);
      final doc = (await tester.runAsync(() => library.watchRecents().first))!;
      expect(doc.single.uri, '$tree/document/sem%2Fcalc');
      expect(doc.single.canReopen, isTrue);
    });
  });

  group('selecting several documents (FR-FILE-011)', () {
    Future<void> openTwo(WidgetTester tester) async {
      await launch(tester);
      await openPicked(tester, pdf(1, 'Calculus.pdf'));
      await closeReader(tester);
      await openPicked(tester, pdf(2, 'Physics.pdf'));
      await closeReader(tester);
    }

    testWidgets(
      'long press selects, taps add, and one confirmation deletes all',
      (tester) async {
        await openTwo(tester);
        await tester.longPress(find.text('Calculus.pdf'));
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsOneWidget);
        // While selecting, a tap selects instead of opening.
        await tester.tap(find.text('Physics.pdf'));
        await tester.pumpAndSettle();
        expect(find.byType(ReaderPage), findsNothing);
        expect(find.text('2 selected'), findsOneWidget);

        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        expect(find.text('Delete 2 documents?'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Delete'));
        await tester.pumpAndSettle();
        expect(files.calls, [
          'delete content://provider/1',
          'delete content://provider/2',
        ]);
        expect(find.text('Calculus.pdf'), findsNothing);
        expect(find.text('Physics.pdf'), findsNothing);
        expect(find.textContaining('selected'), findsNothing);
      },
    );

    testWidgets('a partly failed batch says how many were not changed', (
      tester,
    ) async {
      files.failing.add('content://provider/2');
      await openTwo(tester);
      await tester.longPress(find.text('Calculus.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(
        find.text('1 of 2 documents could not be changed.'),
        findsOneWidget,
      );
      expect(find.text('Calculus.pdf'), findsNothing);
      expect(find.text('Physics.pdf'), findsOneWidget);
    });

    testWidgets('back and a tab change leave selection mode, not the screen', (
      tester,
    ) async {
      await openTwo(tester);
      await tester.longPress(find.text('Calculus.pdf'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
      expect(find.text('Calculus.pdf'), findsOneWidget);

      await tester.longPress(find.text('Calculus.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('removing a selection from recents keeps the files', (
      tester,
    ) async {
      await openTwo(tester);
      await tester.longPress(find.text('Calculus.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Physics.pdf'));
      await tester.pumpAndSettle();
      // Neither was opened from a library folder.
      expect(find.byTooltip('Move'), findsNothing);
      await tester.tap(find.byTooltip('Remove from recents'));
      await tester.pumpAndSettle();
      expect(find.text('Calculus.pdf'), findsNothing);
      expect(find.text('Physics.pdf'), findsNothing);
      expect(files.calls, isEmpty);
    });

    testWidgets('PDFs selected in a folder move together to one folder', (
      tester,
    ) async {
      folders.listings[null] = [
        folderEntry('a', 'A.pdf'),
        folderEntry('b', 'B.pdf'),
        folderEntry('sem', 'Semester 1', dir: true),
      ];
      await launch(tester);
      folders.picked = PlatformFolder(treeUri: tree, displayName: 'Books');
      await tester.tap(find.text('Folders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('A.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      // Folders are not selected.
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Move'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semester 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move here'));
      await tester.pumpAndSettle();
      expect(files.calls, [
        'move $tree/document/a $tree sem',
        'move $tree/document/b $tree sem',
      ]);
      expect(find.textContaining('selected'), findsNothing);
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
