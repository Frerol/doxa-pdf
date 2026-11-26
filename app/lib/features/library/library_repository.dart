// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:drift/drift.dart';

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
}
