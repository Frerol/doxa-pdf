// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'library_database.g.dart';

/// Documents the user has opened (docs/plan/03-architecture.md §7): where
/// they are, their reading state, and whether they are listed in recents
/// and favorites (FR-FILE-004, FR-FILE-005, FR-BOOK-002, FR-VIEW-006).
///
/// A row is keyed by the document's [identity], so renaming or moving the
/// file keeps its reading state. Annotations are never stored here: they
/// live in the PDF.
@DataClassName('DocumentRow')
class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// See `documentIdentity`.
  TextColumn get identity => text().unique()();

  /// Where to reopen the file: a `content:` URI with a persisted grant on
  /// Android, or a `file:` URI. Null when the file cannot be reopened
  /// (a shared file without a persistable grant).
  TextColumn get uri => text().nullable()();

  TextColumn get displayName => text()();

  /// Zero until the document has been opened once.
  IntColumn get pageCount => integer().withDefault(const Constant(0))();

  /// Reading position: a zero-based page and a point of it, as fractions
  /// of the page size, plus the zoom (see `ReadingState`).
  IntColumn get page => integer().withDefault(const Constant(0))();
  RealColumn get pageX => real().withDefault(const Constant(0))();
  RealColumn get pageY => real().withDefault(const Constant(0))();
  RealColumn get zoom => real().withDefault(const Constant(1))();

  /// Right-to-left page order is per document (FR-VIEW-019).
  BoolColumn get rightToLeft => boolean().withDefault(const Constant(false))();

  BoolColumn get favorite => boolean().withDefault(const Constant(false))();

  /// False once the user removes the document from recents. The row stays,
  /// so its reading state comes back if the file is opened again.
  BoolColumn get inRecents => boolean().withDefault(const Constant(true))();

  DateTimeColumn get lastOpenedAt => dateTime()();
}

@DriftDatabase(tables: [Documents])
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase(super.executor);

  /// Opens the database file in [directory], on a background isolate.
  factory LibraryDatabase.inDirectory(String directory) => LibraryDatabase(
    NativeDatabase.createInBackground(File('$directory/library.sqlite')),
  );

  /// A database in memory (tests).
  factory LibraryDatabase.memory() => LibraryDatabase(NativeDatabase.memory());

  /// Bump on every schema change, add a migration step, and run
  /// `dart run drift_dev make-migrations` in `app/` to save the new schema
  /// for the migration tests.
  @override
  int get schemaVersion => 1;
}
