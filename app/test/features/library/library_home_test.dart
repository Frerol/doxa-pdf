// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/library/library_database.dart';
import 'package:doxa_pdf/features/library/library_home.dart';
import 'package:doxa_pdf/features/library/library_repository.dart';
import 'package:doxa_pdf/features/reader/reader_page.dart';
import 'package:doxa_pdf/features/reader/reader_tabs.dart';
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

  /// Opens a home section's full list with its "See all" (UX §5).
  Future<void> seeAll(WidgetTester tester, String section) async {
    final header = find.byKey(ValueKey('section-$section'));
    final inHeader = find.descendant(
      of: header,
      matching: find.text('See all'),
    );
    final button = inHeader.evaluate().isEmpty ? header : inHeader;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Back from a full list to the dashboard.
  Future<void> backHome(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
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
      await seeAll(tester, 'recents');
      await tester.tap(find.byTooltip('Add to favorites'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from recents'));
      await tester.pumpAndSettle();
      expect(find.text('Calculus.pdf'), findsNothing);

      await backHome(tester);
      await seeAll(tester, 'favorites');
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

  group('dashboard (UX §5)', () {
    Future<void> seed(String name, int id, {bool favorite = false}) async {
      final p = pdf(id, name);
      documents.persisted[p.uri] = p;
      final doc = await library.recordOpen(
        identity: 'id:${p.path}',
        displayName: name,
        uri: p.uri,
      );
      await library.saveState(doc.id, (
        page: 11 + id,
        x: 0,
        y: 0,
        zoom: 1,
        rightToLeft: false,
      ), pageCount: 20);
      if (favorite) await library.setFavorite(doc.id, true);
    }

    testWidgets('Continue reading reopens the last document where it was', (
      tester,
    ) async {
      await seed('Physics.pdf', 1);
      await seed('Calculus.pdf', 2, favorite: true);
      await launch(tester);
      expect(find.text('CONTINUE READING'), findsOneWidget);
      // The last one opened is the one to continue; the other is a recent.
      expect(find.text('Continue on p. 14'), findsOneWidget);
      await tester.tap(find.text('Continue on p. 14'));
      await tester.pumpAndSettle();
      final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
      expect(reader.title, 'Calculus.pdf');
      expect(reader.initialPosition?.page, 13);
    });

    testWidgets('See all opens a section and back returns to it', (
      tester,
    ) async {
      await seed('Physics.pdf', 1, favorite: true);
      await seed('Calculus.pdf', 2);
      await launch(tester);
      await seeAll(tester, 'favorites');
      expect(find.widgetWithText(AppBar, 'Favorites'), findsOneWidget);
      expect(find.text('Physics.pdf'), findsOneWidget);
      expect(find.text('Calculus.pdf'), findsNothing);
      await backHome(tester);
      expect(find.text('CONTINUE READING'), findsOneWidget);
    });

    for (final (name, size) in [
      ('phone', const Size(360, 780)),
      ('tablet', const Size(1280, 800)),
    ]) {
      testWidgets('fits a $name at the largest text size (UX §6)', (
        tester,
      ) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await seed(
          'A long name of a textbook on calculus.pdf',
          1,
          favorite: true,
        );
        await seed('Physics.pdf', 2, favorite: true);
        await seed('Anatomy.pdf', 3);
        folders.picked = PlatformFolder(treeUri: tree, displayName: 'Books');
        await launch(tester);
        Future<void> scrollTo(Finder target) async {
          for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
            await tester.drag(find.byType(ListView), const Offset(0, -300));
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
        }

        await scrollTo(find.text('Add folder'));
        await tester.tap(find.text('Add folder'));
        await tester.pumpAndSettle();
        await scrollTo(find.text('Books'));
        expect(find.text('Books'), findsOneWidget);
        // A layout overflow anywhere on the way fails the test.
        expect(tester.takeException(), isNull);
      });
    }
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
      // The tab stays open, so its source is still leased (FR-FILE-007).
      expect(documents.released, isEmpty);
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
      await seeAll(tester, 'folders');
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
      // Document menus are in the full lists, not on the dashboard.
      if (find.byTooltip('Show menu').evaluate().isEmpty) {
        await seeAll(tester, 'recents');
      }
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
      await seeAll(tester, 'recents');
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
      await seeAll(tester, 'recents');
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

    testWidgets('back leaves selection mode first, then the full list', (
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
      await backHome(tester);
      await backHome(tester);
      expect(find.textContaining('selected'), findsNothing);
      expect(find.text('Continue reading'.toUpperCase()), findsOneWidget);
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

  group('tabs (FR-FILE-007)', () {
    String shownTitle(WidgetTester tester) =>
        tester.widget<ReaderPage>(find.byType(ReaderPage)).title;

    Future<void> openBoth(WidgetTester tester) async {
      await launch(tester);
      await openPicked(tester, pdf(1, 'Calculus.pdf'));
      await closeReader(tester);
      await openPicked(tester, pdf(2, 'Physics.pdf'));
    }

    testWidgets('a document opened from home joins the open tabs', (
      tester,
    ) async {
      await openBoth(tester);
      expect(shownTitle(tester), 'Physics.pdf');
      expect(find.byTooltip('Close Calculus.pdf'), findsOneWidget);
      expect(find.byTooltip('Close Physics.pdf'), findsOneWidget);
      // Inactive tabs hold no document in the engine (NFR-PERF-006).
      expect(engine.openDocumentCount, 1);
    });

    testWidgets('switching back shows the tab where it was left', (
      tester,
    ) async {
      final first = pdf(1, 'Calculus.pdf');
      documents.persisted[first.uri] = first;
      final doc = await library.recordOpen(
        identity: 'id:${first.path}',
        displayName: first.displayName,
        uri: first.uri,
      );
      await library.saveState(doc.id, (
        page: 12,
        x: 0,
        y: 0,
        zoom: 1,
        rightToLeft: true,
      ), pageCount: 20);
      await launch(tester);
      await tester.tap(find.text('Calculus.pdf'));
      await tester.pumpAndSettle();
      await closeReader(tester);
      await openPicked(tester, pdf(2, 'Physics.pdf'));

      await tester.tap(find.text('Calculus.pdf'));
      await tester.pumpAndSettle();
      final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
      expect(reader.title, 'Calculus.pdf');
      expect(reader.initialPosition?.page, 12);
      expect(reader.initialRightToLeft, isTrue);
      expect(engine.openDocumentCount, 1);
    });

    testWidgets('opening an open document shows its tab, not a second one', (
      tester,
    ) async {
      await openBoth(tester);
      await closeReader(tester);
      await tester.tap(find.text('Calculus.pdf'));
      await tester.pumpAndSettle();
      expect(shownTitle(tester), 'Calculus.pdf');
      expect(find.byTooltip('Close Calculus.pdf'), findsOneWidget);
      // The extra lease from reopening went back at once.
      expect(documents.released, [1]);
    });

    testWidgets('closing tabs shows the one to the left, then home', (
      tester,
    ) async {
      await openBoth(tester);
      await tester.tap(find.byTooltip('Close Physics.pdf'));
      await tester.pumpAndSettle();
      expect(shownTitle(tester), 'Calculus.pdf');
      expect(documents.released, [2]);

      await tester.tap(find.byTooltip('Close Calculus.pdf'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage), findsNothing);
      expect(find.text('Open file'), findsOneWidget);
      expect(documents.released, [2, 1]);
    });

    testWidgets('a phone switches tabs from a grid', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openBoth(tester);
      expect(find.byType(ReaderTabRow), findsNothing);

      await tester.tap(find.byTooltip('2 open tabs'));
      await tester.pumpAndSettle();
      expect(find.byType(TabSwitcher), findsOneWidget);
      await tester.tap(find.text('Calculus.pdf'));
      await tester.pumpAndSettle();
      expect(shownTitle(tester), 'Calculus.pdf');

      await tester.tap(find.byTooltip('2 open tabs'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close Physics.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('Physics.pdf'), findsNothing);
      expect(documents.released, [2]);
    });

    testWidgets('open tabs are saved for the next start', (tester) async {
      await openBoth(tester);
      final saved = (await tester.runAsync(library.openTabs))!;
      expect(saved.documents.map((d) => d.displayName), [
        'Calculus.pdf',
        'Physics.pdf',
      ]);
      expect(saved.active, 1);
    });

    testWidgets('saved tabs come back after a restart, each reopened', (
      tester,
    ) async {
      final first = pdf(1, 'Calculus.pdf');
      final second = pdf(2, 'Physics.pdf');
      documents.persisted[first.uri] = first;
      documents.persisted[second.uri] = second;
      final ids = <int>[];
      for (final p in [first, second]) {
        final doc = await library.recordOpen(
          identity: 'id:${p.path}',
          displayName: p.displayName,
          uri: p.uri,
        );
        ids.add(doc.id);
      }
      await library.saveOpenTabs(ids, active: 0);

      await launch(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(shownTitle(tester), 'Calculus.pdf');
      expect(find.byTooltip('Close Physics.pdf'), findsOneWidget);
      // Only the shown tab's file was reopened.
      expect(engine.openDocumentCount, 1);

      await tester.tap(find.text('Physics.pdf'));
      await tester.pumpAndSettle();
      expect(shownTitle(tester), 'Physics.pdf');
    });

    testWidgets('a saved tab whose file is gone closes and says so', (
      tester,
    ) async {
      final gone = pdf(1, 'Gone.pdf');
      final doc = await library.recordOpen(
        identity: 'id:${gone.path}',
        displayName: gone.displayName,
        uri: gone.uri,
      );
      await library.saveOpenTabs([doc.id], active: 0);

      await launch(tester);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderPage), findsNothing);
      expect(find.textContaining('no longer be opened'), findsOneWidget);
      final recents = (await tester.runAsync(
        () => library.watchRecents().first,
      ))!;
      expect(recents.single.canReopen, isFalse);
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
