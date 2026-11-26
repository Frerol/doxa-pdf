// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_pdf/features/reader/reader_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final released = <String>[];
  ReaderTab tab(String key) => ReaderTab(
    key: key,
    title: key,
    source: FileSource('/$key'),
    release: () async => released.add(key),
  );
  setUp(released.clear);

  group('reader tabs (FR-FILE-007)', () {
    test('moving a tab keeps the shown one shown', () {
      final tabs = ReaderTabs()
        ..open(tab('a'))
        ..open(tab('b'))
        ..open(tab('c'))
        ..activate(0);
      tabs.move(0, 2);
      expect(tabs.tabs.map((t) => t.key), ['b', 'c', 'a']);
      expect(tabs.active?.key, 'a');
      tabs.move(2, 0);
      expect(tabs.tabs.map((t) => t.key), ['a', 'b', 'c']);
      expect(tabs.activeIndex, 0);
    });

    test('closing a tab left of the shown one keeps showing it', () async {
      final tabs = ReaderTabs()
        ..open(tab('a'))
        ..open(tab('b'))
        ..open(tab('c'));
      tabs.close(0);
      expect(tabs.active?.key, 'c');
      await pumpEventQueue();
      expect(released, ['a']);
    });

    test('a restored tab gets its source once, then releases it', () async {
      var reopened = 0;
      final restored = ReaderTab(
        key: 'r',
        title: 'r',
        reopen: () async {
          reopened++;
          return (
            source: const FileSource('/r') as DocumentSource,
            release: () async => released.add('r'),
          );
        },
      );
      final tabs = ReaderTabs()..restore([restored], active: 0);
      await Future.wait([tabs.acquire(restored), tabs.acquire(restored)]);
      expect(reopened, 1);
      tabs.close(0);
      await pumpEventQueue();
      expect(released, ['r']);
    });
  });
}
