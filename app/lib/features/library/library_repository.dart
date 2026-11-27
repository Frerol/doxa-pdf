// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:drift/drift.dart';

import '../reader/reader_geometry.dart';
import 'library_database.dart';

/// Where the reader was in a document (FR-VIEW-006): a zero-based page and
/// a point of it as fractions of the page size, the zoom, and the
/// per-document right-to-left page order (FR-VIEW-019).
typedef ReadingState = ({
  int page,
  double x,
  double y,
  double zoom,
  bool rightToLeft,
});

/// A document as the library lists it.
final class LibraryDocument {
  LibraryDocument._(DocumentRow row)
    : id = row.id,
      identity = row.identity,
      uri = row.uri,
      displayName = row.displayName,
      pageCount = row.pageCount,
      favorite = row.favorite,
      lastOpenedAt = row.lastOpenedAt,
      state = (
        page: row.page,
        x: row.pageX,
        y: row.pageY,
        zoom: row.zoom,
        rightToLeft: row.rightToLeft,
      );

  final int id;
  final String identity;

  /// See [Documents.uri].
  final String? uri;
  final String displayName;
  final int pageCount;
  final bool favorite;
  final DateTime lastOpenedAt;
  final ReadingState state;

  /// Reading progress from 0 to 1 (FR-BOOK-002): the share of pages up to
  /// and including the current one. Zero before the first open.
  double get progress =>
      pageCount == 0 ? 0 : ((state.page + 1) / pageCount).clamp(0, 1);

  bool get canReopen => uri != null;
}

/// The library's documents: recents, favorites and reading state
/// (issue #50). Every method is safe to call from the UI isolate; drift
/// runs the queries on its own isolate.
final class LibraryRepository {
  LibraryRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LibraryDatabase _db;
  final DateTime Function() _clock;

  /// Records that the document with [identity] was opened from [uri], and
  /// returns it with its saved reading state. The document is listed in
  /// recents again even if the user removed it before.
  ///
  /// A known document keeps its row, so its state and favorite survive a
  /// rename or a move. A null [uri] keeps the last reopenable location.
  Future<LibraryDocument> recordOpen({
    required String identity,
    required String displayName,
    String? uri,
  }) {
    return _db.transaction(() async {
      final now = _clock();
      final existing = await (_db.select(
        _db.documents,
      )..where((d) => d.identity.equals(identity))).getSingleOrNull();
      if (existing == null) {
        final id = await _db
            .into(_db.documents)
            .insert(
              DocumentsCompanion.insert(
                identity: identity,
                displayName: displayName,
                uri: Value(uri),
                lastOpenedAt: now,
                zoom: const Value(fitReadingZoom),
              ),
            );
        return _byId(id);
      }
      await (_db.update(
        _db.documents,
      )..where((d) => d.id.equals(existing.id))).write(
        DocumentsCompanion(
          displayName: Value(displayName),
          uri: uri == null ? const Value.absent() : Value(uri),
          inRecents: const Value(true),
          lastOpenedAt: Value(now),
        ),
      );
      return _byId(existing.id);
    });
  }

  Future<LibraryDocument> _byId(int id) async => LibraryDocument._(
    await (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(id))).getSingle(),
  );

  /// Saves where the reader is in document [id], and its page count.
  Future<void> saveState(int id, ReadingState state, {int? pageCount}) =>
      (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
        DocumentsCompanion(
          page: Value(state.page),
          pageX: Value(state.x),
          pageY: Value(state.y),
          zoom: Value(state.zoom),
          rightToLeft: Value(state.rightToLeft),
          pageCount: pageCount == null
              ? const Value.absent()
              : Value(pageCount),
        ),
      );

  /// Recent documents, most recently opened first (FR-FILE-004).
  Stream<List<LibraryDocument>> watchRecents() =>
      _watch((d) => d.inRecents.equals(true));

  /// Favorite documents, most recently opened first (FR-FILE-005).
  Stream<List<LibraryDocument>> watchFavorites() =>
      _watch((d) => d.favorite.equals(true));

  Stream<List<LibraryDocument>> _watch(
    Expression<bool> Function($DocumentsTable d) filter,
  ) {
    final query = _db.select(_db.documents)
      ..where(filter)
      ..orderBy([
        (d) => OrderingTerm.desc(d.lastOpenedAt),
        (d) => OrderingTerm.desc(d.id),
      ]);
    return query.watch().map(
      (rows) => [for (final row in rows) LibraryDocument._(row)],
    );
  }

  /// Records document [id] as read now, for example when its tab is shown
  /// again: it moves to the top of recents and of "Continue reading"
  /// (FR-FILE-004, FR-BOOK-002).
  Future<void> markRead(int id) =>
      (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
        DocumentsCompanion(
          inRecents: const Value(true),
          lastOpenedAt: Value(_clock()),
        ),
      );

  Future<void> setFavorite(int id, bool favorite) =>
      (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
        DocumentsCompanion(favorite: Value(favorite)),
      );

  /// Hides document [id] from recents (FR-FILE-004). Its reading state is
  /// kept for the next time the file is opened.
  Future<void> removeFromRecents(int id) =>
      (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
        const DocumentsCompanion(inRecents: Value(false)),
      );

  /// Forgets that document [id] can be reopened from its location, for
  /// example after its grant was lost or the file was deleted elsewhere.
  Future<void> forgetLocation(int id) =>
      (_db.update(_db.documents)..where((d) => d.id.equals(id))).write(
        const DocumentsCompanion(uri: Value(null)),
      );

  /// Records that the file the library reopens from [uri] was renamed or
  /// moved (FR-FILE-011): it now opens from [newUri] under [displayName].
  /// A null [newUri] means it can no longer be reopened from here. The
  /// reading state and favorite stay.
  Future<void> relocate(
    String uri, {
    required String? newUri,
    required String displayName,
  }) => (_db.update(_db.documents)..where((d) => d.uri.equals(uri))).write(
    DocumentsCompanion(uri: Value(newUri), displayName: Value(displayName)),
  );

  /// Forgets the documents opened from [uri] once the file was deleted
  /// (FR-FILE-011), and returns their identities so their thumbnails can be
  /// deleted too.
  Future<List<String>> forgetDeleted(String uri) => _db.transaction(() async {
    final rows = await (_db.select(
      _db.documents,
    )..where((d) => d.uri.equals(uri))).get();
    await (_db.delete(_db.documents)..where((d) => d.uri.equals(uri))).go();
    return [for (final row in rows) row.identity];
  });
}

/// A folder in the library (FR-FILE-006).
final class LibraryFolder {
  LibraryFolder._(LibraryFolderRow row)
    : id = row.id,
      treeUri = row.treeUri,
      displayName = row.displayName;

  final int id;
  final String treeUri;
  final String displayName;
}

/// The folders the user added to the library (FR-FILE-006).
extension LibraryFoldersRepository on LibraryRepository {
  /// Folders by name.
  Stream<List<LibraryFolder>> watchFolders() {
    final query = _db.select(_db.folders)
      ..orderBy([
        (f) => OrderingTerm.asc(f.displayName.collate(Collate.noCase)),
        (f) => OrderingTerm.asc(f.id),
      ]);
    return query.watch().map(
      (rows) => [for (final row in rows) LibraryFolder._(row)],
    );
  }

  /// Adds a folder; adding the same folder again only updates its name.
  Future<void> addFolder({
    required String treeUri,
    required String displayName,
  }) => _db
      .into(_db.folders)
      .insert(
        FoldersCompanion.insert(
          treeUri: treeUri,
          displayName: displayName,
          addedAt: _clock(),
        ),
        onConflict: DoUpdate(
          (_) => FoldersCompanion(displayName: Value(displayName)),
          target: [_db.folders.treeUri],
        ),
      );

  /// Removes a folder from the library; its files are not touched.
  Future<void> removeFolder(int id) =>
      (_db.delete(_db.folders)..where((f) => f.id.equals(id))).go();
}

/// The documents open in tabs, kept across restarts (FR-FILE-007).
extension OpenTabsRepository on LibraryRepository {
  /// Replaces the saved tabs with [documentIds], left to right, the one at
  /// [active] shown.
  Future<void> saveOpenTabs(List<int> documentIds, {required int active}) =>
      _db.transaction(() async {
        await _db.delete(_db.openTabs).go();
        await _db.batch(
          (batch) => batch.insertAll(_db.openTabs, [
            for (final (i, id) in documentIds.indexed)
              OpenTabsCompanion.insert(
                documentId: Value(id),
                position: i,
                active: Value(i == active),
              ),
          ]),
        );
      });

  /// The saved tabs, left to right, and which one was shown. Documents that
  /// are gone or can no longer be reopened are left out.
  Future<({List<LibraryDocument> documents, int active})> openTabs() async {
    final query = _db.select(_db.openTabs).join([
      innerJoin(
        _db.documents,
        _db.documents.id.equalsExp(_db.openTabs.documentId),
      ),
    ])..orderBy([OrderingTerm.asc(_db.openTabs.position)]);
    final documents = <LibraryDocument>[];
    var active = 0;
    for (final row in await query.get()) {
      final document = LibraryDocument._(row.readTable(_db.documents));
      if (!document.canReopen) continue;
      if (row.readTable(_db.openTabs).active) active = documents.length;
      documents.add(document);
    }
    return (documents: documents, active: active);
  }
}

/// Where the thumbnails of the library's documents are kept.
final class ThumbnailStore {
  ThumbnailStore(this.directory);

  final String directory;

  File fileFor(String identity) => File('$directory/$identity.png');

  /// Writes [png] atomically, so a reader never sees half a file.
  Future<void> write(String identity, List<int> png) async {
    final file = fileFor(identity);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(png, flush: true);
    await temp.rename(file.path);
  }

  /// Deletes the thumbnail of a document whose file was deleted.
  Future<void> delete(String identity) async {
    final file = fileFor(identity);
    if (await file.exists()) await file.delete();
  }
}
