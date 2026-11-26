// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_pdf/features/library/library_database.dart';
import 'package:doxa_pdf/features/library/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LibraryDatabase db;
  late LibraryRepository library;
  var now = DateTime(2026, 11, 26, 9);

  setUp(() {
    db = LibraryDatabase.memory();
    now = DateTime(2026, 11, 26, 9);
    library = LibraryRepository(db, clock: () => now);
  });
  tearDown(() => db.close());

  Future<LibraryDocument> open(
    String identity, {
    String name = 'Book.pdf',
    String? uri = 'content://book',
  }) {
    now = now.add(const Duration(minutes: 1));
    return library.recordOpen(identity: identity, displayName: name, uri: uri);
  }

  const state = (page: 41, x: 0.25, y: 0.5, zoom: 2.0, rightToLeft: true);

  group('reading state (FR-VIEW-006)', () {
    test('is restored on reopen', () async {
      final first = await open('a');
      expect(first.state.page, 0);
      await library.saveState(first.id, state, pageCount: 100);
      final again = await open('a');
      expect(again.state, state);
      expect(again.pageCount, 100);
    });

    test('survives a rename or move of the same file', () async {
      final first = await open('a');
      await library.saveState(first.id, state, pageCount: 100);
      await library.setFavorite(first.id, true);
      final moved = await open('a', name: 'Renamed.pdf', uri: 'content://x');
      expect(moved.id, first.id);
      expect(moved.state, state);
      expect(moved.favorite, isTrue);
      expect(moved.displayName, 'Renamed.pdf');
      expect(moved.uri, 'content://x');
    });

    test('a reopen without a location keeps the last one', () async {
      await open('a', uri: 'content://book');
      final again = await open('a', uri: null);
      expect(again.uri, 'content://book');
      expect(again.canReopen, isTrue);
    });
  });

  group('recents (FR-FILE-004, FR-BOOK-002)', () {
    test('lists the most recently opened first', () async {
      await open('a', name: 'A');
      await open('b', name: 'B');
      await open('a', name: 'A');
      final recents = await library.watchRecents().first;
      expect(recents.map((d) => d.displayName), ['A', 'B']);
    });

    test(
      'a removed document comes back, with its state, when opened',
      () async {
        final doc = await open('a');
        await library.saveState(doc.id, state, pageCount: 100);
        await library.removeFromRecents(doc.id);
        expect(await library.watchRecents().first, isEmpty);
        final again = await open('a');
        expect(again.state, state);
        expect((await library.watchRecents().first).single.id, doc.id);
      },
    );

    test('progress grows with the page and reaches 1 on the last', () async {
      final doc = await open('a');
      Future<double> progressAt(int page) async {
        await library.saveState(doc.id, (
          page: page,
          x: 0,
          y: 0,
          zoom: 1,
          rightToLeft: false,
        ), pageCount: 10);
        return (await library.watchRecents().first).single.progress;
      }

      final early = await progressAt(1);
      final late_ = await progressAt(5);
      expect(late_, greaterThan(early));
      expect(await progressAt(9), 1);
    });
  });

  group('favorites (FR-FILE-005)', () {
    test('list only favorites, and removing from recents keeps them', () async {
      final a = await open('a', name: 'A');
      await open('b', name: 'B');
      await library.setFavorite(a.id, true);
      await library.removeFromRecents(a.id);
      final favorites = await library.watchFavorites().first;
      expect(favorites.map((d) => d.displayName), ['A']);
    });
  });
}
