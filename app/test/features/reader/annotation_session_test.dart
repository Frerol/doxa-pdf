// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/library/document_identity.dart';
import 'package:doxa_pdf/features/library/library_database.dart';
import 'package:doxa_pdf/features/library/library_repository.dart';
import 'package:doxa_pdf/features/reader/annotation_layer.dart';
import 'package:doxa_pdf/features/reader/annotation_session.dart';
import 'package:doxa_pdf/features/reader/reader_page.dart';
import 'package:doxa_pdf/l10n/gen/app_localizations.dart';
import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _source = FileSource('book.pdf');
const _before = 'before';

TextMarkup _highlight(String id) {
  return TextMarkup(
    id: id,
    pageIndex: 0,
    kind: MarkupKind.highlight,
    quads: [PdfQuad.fromRect(const PdfRect(10, 10, 20, 20))],
    byDoxa: true,
  );
}

FakePdfEngine _fake([List<Annotation> annotations = const []]) =>
    FakePdfEngine({
      _source.path: FakeDocument(pages: [FakePage(annotations: annotations)]),
    });

class _ObservedEngine implements PdfEngine {
  _ObservedEngine(this.fake);

  final FakePdfEngine fake;
  Future<void> Function()? beforeAdd;
  List<Annotation> Function(List<Annotation>)? normalize;
  Future<SaveResult> Function(String)? saveFile;

  @override
  Future<void> addAnnotations(
    DocumentHandle document,
    List<Annotation> annotations,
  ) async {
    await beforeAdd?.call();
    await fake.addAnnotations(
      document,
      normalize?.call(annotations) ?? annotations,
    );
  }

  @override
  Future<List<Annotation>> annotations(
    DocumentHandle document,
    int pageIndex,
  ) => fake.annotations(document, pageIndex);

  @override
  Future<void> deleteAnnotations(
    DocumentHandle document,
    int pageIndex,
    List<String> ids,
  ) => fake.deleteAnnotations(document, pageIndex, ids);

  @override
  Future<int> signatureCount(DocumentHandle document) =>
      fake.signatureCount(document);

  @override
  Future<SaveResult> save(DocumentHandle document, String path) async {
    final result = await fake.save(document, path);
    return await saveFile?.call(path) ?? result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<AnnotationSession> _session(
  LibraryRepository library,
  LibraryDocument row,
  _ObservedEngine engine, {
  required String path,
  bool autosave = false,
  String? identity,
  Timer Function(Duration, void Function()) startTimer = Timer.new,
}) async {
  final opened = await engine.fake.open(_source) as DocumentOpened;
  final session = AnnotationSession(
    library: library,
    documentId: row.id,
    location: row.uri!,
    displayName: row.displayName,
    baseIdentity: identity ?? row.identity,
    path: path,
    engine: engine,
    document: opened.handle,
    pageCount: opened.info.pageCount,
    annotations: DocumentAnnotations(engine, opened.handle),
    reloadPage: (_) {},
    onError: (_) {},
    autosave: autosave,
    startTimer: startTimer,
  );
  await session.preparePage(0);
  addTearDown(session.dispose);
  return session;
}

Future<LibraryDocument> _record(LibraryRepository library, String path) =>
    library.recordOpen(
      identity: _before,
      uri: File(path).absolute.uri.toString(),
      displayName: 'Book.pdf',
    );

class _Clock implements Timer {
  Duration _remaining = Duration.zero;
  void Function()? _callback;

  Timer start(Duration delay, void Function() callback) {
    _remaining = delay;
    _callback = callback;
    return this;
  }

  bool elapse(Duration elapsed) {
    if (_callback == null) return false;
    _remaining -= elapsed;
    if (_remaining > Duration.zero) return false;
    final callback = _callback!;
    _callback = null;
    callback();
    return true;
  }

  @override
  bool get isActive => _callback != null;

  @override
  int get tick => 0;

  @override
  void cancel() => _callback = null;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late LibraryDatabase db;
  late LibraryRepository library;
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('doxa-journal-test-');
    db = LibraryDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    await db.select(db.documents).get();
    library = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'FR-SAVE-003 commits the journal before the engine receives the edit',
    () async {
      final row = await _record(library, _source.path);
      final engine = _ObservedEngine(_fake());
      final session = await _session(library, row, engine, path: _source.path);
      final annotation = _highlight(DoxaMarker.newId());
      var called = false;
      engine.beforeAdd = () async {
        called = true;
        final journal = (await library.journalFor(row.id))!;
        expect(
          (await library.journalCommands(journal)).single,
          isA<AddAnnotations>(),
        );
        expect(session.annotations.page(0)[annotation.id], annotation);
      };
      await session.apply(AddAnnotations([annotation]));
      expect(called, isTrue);
    },
  );

  test(
    'FR-SAVE-003 restores a durable log after restart as one undo step',
    () async {
      final disk = LibraryDatabase.inDirectory(directory.path);
      final original = LibraryRepository(disk);
      final row = await _record(original, _source.path);
      final before = await _session(
        original,
        row,
        _ObservedEngine(_fake()),
        path: _source.path,
      );
      final first = _highlight(DoxaMarker.newId());
      final second = _highlight(DoxaMarker.newId());
      await before.apply(AddAnnotations([first]));
      await before.apply(AddAnnotations([second]));
      await disk.close();

      final reopened = LibraryDatabase.inDirectory(directory.path);
      addTearDown(reopened.close);
      final recovered = LibraryRepository(reopened);
      expect(
        (await recovered.watchRecents().first).single.hasUnsavedChanges,
        isTrue,
      );
      final after = await _session(
        recovered,
        row,
        _ObservedEngine(_fake()),
        path: _source.path,
      );
      expect(await after.restore((await recovered.journalFor(row.id))!), 0);
      expect(await after.engine.annotations(after.document, 0), [
        first,
        second,
      ]);
      await after.undo();
      expect(await after.engine.annotations(after.document, 0), isEmpty);
      expect(after.canUndo, isFalse);
      await after.redo();
      expect(await after.engine.annotations(after.document, 0), [
        first,
        second,
      ]);
      final journal = (await recovered.journalFor(row.id))!;
      final commands = await recovered.journalCommands(journal);
      expect(commands, hasLength(4));
      final replay = AnnotationStore();
      for (final command in commands.take(3)) {
        replay.apply(command);
      }
      expect(replay.page(0), isEmpty);
      replay.apply(commands.last);
      expect(replay.page(0).values, [first, second]);
    },
  );

  test('FR-SAVE-003 a changed file skips entries that no longer fit', () async {
    final row = await _record(library, _source.path);
    final before = await _session(
      library,
      row,
      _ObservedEngine(_fake()),
      path: _source.path,
    );
    final duplicate = _highlight(DoxaMarker.newId());
    final remaining = _highlight(DoxaMarker.newId());
    await before.apply(AddAnnotations([duplicate]));
    await before.apply(AddAnnotations([remaining]));
    final after = await _session(
      library,
      row,
      _ObservedEngine(_fake([duplicate])),
      path: _source.path,
      identity: 'changed',
    );
    expect(await after.restore((await library.journalFor(row.id))!), 1);
    expect(await after.engine.annotations(after.document, 0), [
      duplicate,
      remaining,
    ]);
    await after.undo();
    expect(await after.engine.annotations(after.document, 0), [duplicate]);
  });

  test(
    'FR-SAVE-003 verified save publishes identity and journal removal together',
    () async {
      final path = '${directory.path}/book.pdf';
      final row = await _record(library, path);
      final engine = _ObservedEngine(_fake());
      engine.saveFile = (path) async {
        await File(path).writeAsString('saved bytes');
        return const Saved(11);
      };
      final session = await _session(library, row, engine, path: path);
      await session.apply(AddAnnotations([_highlight(DoxaMarker.newId())]));
      final observed = library.watchRecents().take(2).toList();
      expect(
        (await library.watchRecents().first).single.hasUnsavedChanges,
        isTrue,
      );
      expect(await session.save(), isTrue);
      final [dirty, clean] = await observed;
      expect(dirty.single.identity, _before);
      expect(dirty.single.hasUnsavedChanges, isTrue);
      expect(clean.single.identity, documentIdentitySync(path));
      expect(clean.single.hasUnsavedChanges, isFalse);
      expect(await library.journalFor(row.id), isNull);
      expect(session.hasUnsavedChanges, isFalse);
    },
  );

  test(
    'FR-SAVE-003 undo after a save replays against the saved representation',
    () async {
      final path = '${directory.path}/book.pdf';
      final row = await _record(library, path);
      final annotation = _highlight(DoxaMarker.newId());
      final persisted = annotation.copyWith(
        modified: DateTime.utc(2026, 11, 28),
      );
      final engine = _ObservedEngine(_fake())
        ..normalize = ((_) => [persisted])
        ..saveFile = (path) async {
          await File(path).writeAsString('saved bytes');
          return const Saved(11);
        };
      final original = await _session(library, row, engine, path: path);
      await original.apply(AddAnnotations([annotation]));
      expect(await original.save(), isTrue);
      await original.undo();

      final reopened = await _session(
        library,
        row,
        _ObservedEngine(_fake([persisted])),
        path: path,
        identity: documentIdentitySync(path),
      );
      expect(await reopened.restore((await library.journalFor(row.id))!), 0);
      expect(await reopened.engine.annotations(reopened.document, 0), isEmpty);
    },
  );

  test('FR-SAVE-003 failed save keeps the journal and identity', () async {
    final row = await _record(library, _source.path);
    final engine = _ObservedEngine(_fake())
      ..saveFile = (_) async => const SaveFailed(SaveFailure.noSpace);
    final session = await _session(library, row, engine, path: _source.path);
    await session.apply(AddAnnotations([_highlight(DoxaMarker.newId())]));
    expect(await session.save(), isFalse);
    final document = (await library.watchRecents().first).single;
    expect(document.identity, _before);
    expect(document.hasUnsavedChanges, isTrue);
    expect(await library.journalFor(row.id), isNotNull);
  });

  test('FR-SAVE-001 waits for the quiet period and group closure', () async {
    final row = await _record(library, _source.path);
    final engine = _ObservedEngine(_fake())
      ..saveFile = (_) async => const SaveFailed(SaveFailure.noSpace);
    final clock = _Clock();
    final session = await _session(
      library,
      row,
      engine,
      path: _source.path,
      autosave: true,
      startTimer: clock.start,
    );
    final annotation = _highlight(DoxaMarker.newId());
    await session.apply(AddAnnotations([annotation]));
    const tick = Duration(milliseconds: 1);
    expect(clock.elapse(AnnotationSession.quietPeriod - tick), isFalse);
    session.beginGroup();
    await session.apply(DeleteAnnotations([annotation]));
    session.backgroundSave();
    expect(clock.elapse(AnnotationSession.quietPeriod), isFalse);
    expect(engine.fake.saveLog, isEmpty);
    await session.endGroup();
    expect(clock.elapse(AnnotationSession.quietPeriod - tick), isFalse);
    expect(engine.fake.saveLog, isEmpty);
    expect(clock.elapse(tick), isTrue);
    await session.waitForSave();
    expect(engine.fake.saveLog, hasLength(1));
  });

  testWidgets('FR-SAVE-003 asks before restoring onto a changed file', (
    tester,
  ) async {
    final row = (await tester.runAsync(() => _record(library, _source.path)))!;
    final before = await _session(
      library,
      row,
      _ObservedEngine(_fake()),
      path: _source.path,
    );
    final annotation = _highlight(DoxaMarker.newId());
    await tester.runAsync(() => before.apply(AddAnnotations([annotation])));
    final engine = _fake();
    AnnotationSession? opened;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ReaderPage(
          engine: Future.value(engine),
          source: _source,
          title: row.displayName,
          library: library,
          libraryId: row.id,
          journalLocation: row.uri,
          openedIdentity: 'changed',
          onAnnotationSession: (session) => opened = session,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This PDF changed since you edited it. Restore the changes that still fit?',
      ),
      findsOneWidget,
    );
    expect(opened, isNull);
    await tester.tap(find.text('Restore changes'));
    await tester.pumpAndSettle();
    expect(await engine.annotations(opened!.document, 0), [annotation]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
