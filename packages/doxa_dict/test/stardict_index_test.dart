// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:test/test.dart';

StarDictInfo _info(int size, int count, {int bits = 32, int? synonyms}) =>
    StarDictInfo.parse(
      utf8.encode("""
StarDict's dict ifo file
version=3.0.0
bookname=Test dictionary
idxfilesize=$size
wordcount=$count
idxoffsetbits=$bits
${synonyms == null ? '' : 'synwordcount=$synonyms'}
"""),
    );

List<int> _record(String word, List<int> payload) => [
  ...utf8.encode(word),
  0,
  ...payload,
];

List<int> _entry(String word, {int offset = 0, int size = 0}) {
  final data = ByteData(8)
    ..setUint32(0, offset)
    ..setUint32(4, size);
  return _record(word, data.buffer.asUint8List());
}

List<int> _alias(String word, int ordinal) {
  final data = ByteData(4)..setUint32(0, ordinal);
  return _record(word, data.buffer.asUint8List());
}

final _formatError = throwsA(isA<DictionaryFormatException>());

void main() {
  group('.idx', () {
    test('finds exact and ASCII-folded matches in ordinal order', () {
      final bytes = [
        ..._entry('A', offset: 0xffffffff, size: 0xffffffff),
        ..._entry('a'),
        ..._entry('a'),
        ..._entry('aa'),
        ..._entry('Z'),
        ..._entry('Á'),
        ..._entry('á'),
      ];
      final index = StarDictIndex.parse(bytes, _info(bytes.length, 7));
      bytes.fillRange(0, bytes.length, 0);
      expect(index.length, 7);
      expect(index[0], (headword: 'A', offset: 0xffffffff, size: 0xffffffff));
      expect(index[6].headword, 'á');
      expect(index.lookup('A'), [0]);
      expect(index.lookup('a'), [1, 2]);
      expect(index.lookup('a', ignoreAsciiCase: true), [0, 1, 2]);
      expect(index.lookup('aa'), [3]);
      expect(index.lookup('á', ignoreAsciiCase: true), [6]);
      expect(index.lookup('b'), isEmpty);
      expect(index.lookup('a\u0000'), isEmpty);
    });

    test('preserves an initial BOM as part of a headword', () {
      final bytes = _entry('\uFEFFword');
      final index = StarDictIndex.parse(bytes, _info(bytes.length, 1));
      expect(index[0].headword, '\uFEFFword');
      expect(index.lookup(index[0].headword), [0]);
    });

    test('reads the largest supported 64-bit offset', () {
      final bytes = _record('last', [
        0x7f,
        ...List.filled(7, 255),
        0,
        0,
        0,
        42,
      ]);
      final index = StarDictIndex.parse(
        bytes,
        _info(bytes.length, 1, bits: 64),
      );
      expect(index[0].offset, 0x7fffffffffffffff);
      expect(index[0].size, 42);
    });

    test('reads a 64-bit offset above 4 GiB', () {
      final bytes = _record('last', [0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 42]);
      final index = StarDictIndex.parse(
        bytes,
        _info(bytes.length, 1, bits: 64),
      );
      expect(index[0].offset, 0x100000002);
    });

    test('rejects 64-bit offsets at or above 2^63', () {
      final bytes = _record('last', [0x80, ...List.filled(7, 0), 0, 0, 0, 42]);
      expect(
        () => StarDictIndex.parse(bytes, _info(bytes.length, 1, bits: 64)),
        _formatError,
      );
    });

    test('accepts an empty index', () {
      final index = StarDictIndex.parse([], _info(0, 0));
      expect(index.length, 0);
      expect(index.lookup('first'), isEmpty);
    });

    for (final words in [
      ['b', 'a'],
      ['a', 'A'],
      ['AZ', 'aa'],
      ['á', 'Á'],
    ]) {
      test('rejects unsorted words $words', () {
        final bytes = words.expand(_entry).toList();
        expect(
          () => StarDictIndex.parse(bytes, _info(bytes.length, 2)),
          _formatError,
        );
      });
    }

    test('rejects wrong sizes and counts in either direction', () {
      final bytes = _entry('word');
      for (final size in [bytes.length - 1, bytes.length + 1]) {
        expect(() => StarDictIndex.parse(bytes, _info(size, 1)), _formatError);
      }
      for (final count in [0, 2, 9223372036854775807]) {
        expect(
          () => StarDictIndex.parse(bytes, _info(bytes.length, count)),
          _formatError,
        );
      }
    });

    test(
      'rejects missing terminator, truncated payload, and invalid bytes',
      () {
        final full = _entry('word');
        for (final bytes in [
          List.filled(12, 65),
          full.sublist(0, full.length - 1),
          [255, ...full.skip(1)],
          [256, ...full.skip(1)],
        ]) {
          expect(
            () => StarDictIndex.parse(bytes, _info(bytes.length, 1)),
            _formatError,
          );
        }
      },
    );
  });

  group('.idx.gz', () {
    final bytes = _entry('word');
    final compressed = gzip.encode(bytes);
    final info = _info(bytes.length, 1);

    test('uses the decompressed size including across gzip members', () {
      final split = bytes.length ~/ 2;
      final index = StarDictIndex.parse(
        [
          ...gzip.encode(bytes.sublist(0, split)),
          ...gzip.encode(bytes.sublist(split)),
        ],
        info,
        gzip: true,
      );
      expect(index.lookup('word'), [0]);
      expect(
        StarDictIndex.parse(compressed, info, gzip: true)[0].headword,
        'word',
      );
    });

    test('rejects smaller output and stops output above the declared size', () {
      expect(
        () => StarDictIndex.parse(
          compressed,
          _info(bytes.length + 1, 1),
          gzip: true,
        ),
        _formatError,
      );
      final large = gzip.encode([...bytes, ...List.filled(1024 * 1024, 0)]);
      expect(() => StarDictIndex.parse(large, info, gzip: true), _formatError);
    });

    test('rejects a declared size above the hard cap', () {
      expect(
        () => StarDictIndex.parse(
          compressed,
          _info(StarDictIndex.maxGzipIndexSize + 1, 1),
          gzip: true,
        ),
        _formatError,
      );
    });

    test('rejects malformed gzip streams', () {
      final corrupt = [...compressed];
      corrupt[corrupt.length - 8] ^= 1;
      for (final input in [
        <int>[1, 2, 3],
        corrupt,
        compressed.sublist(0, compressed.length - 1),
        zlib.encode(bytes),
        [...compressed, 0],
        [...compressed, ...gzip.encode([]).take(13)],
        <int>[],
      ]) {
        expect(
          () => StarDictIndex.parse(input, info, gzip: true),
          _formatError,
          reason: 'stream bytes: $input',
        );
      }
      expect(
        () => StarDictIndex.parse([], _info(0, 0), gzip: true),
        _formatError,
      );
    });
  });

  group('.syn', () {
    test('returns all aliases with duplicate keys in file order', () {
      final bytes = [
        ..._alias('Link', 2),
        ..._alias('link', 1),
        ..._alias('link', 0),
        ..._alias('other', 2),
      ];
      final synonyms = StarDictSynonyms.parse(bytes, _info(0, 3, synonyms: 4));
      expect(synonyms.length, 4);
      expect(synonyms.aliasAt(0), 'Link');
      expect(synonyms.ordinalAt(3), 2);
      expect(synonyms.lookup('link'), [1, 0]);
      expect(synonyms.lookup('link', ignoreAsciiCase: true), [2, 1, 0]);
      expect(synonyms.lookup('other'), [2]);
      expect(synonyms.lookup('unknown'), isEmpty);
    });

    test('requires a matching declared count, including for an empty file', () {
      final bytes = _alias('alias', 0);
      for (final count in [null, 0, 2]) {
        expect(
          () => StarDictSynonyms.parse(bytes, _info(0, 1, synonyms: count)),
          _formatError,
        );
      }
      expect(() => StarDictSynonyms.parse([], _info(0, 1)), _formatError);
      expect(StarDictSynonyms.parse([], _info(0, 1, synonyms: 0)).length, 0);
    });

    test('rejects out-of-range ordinals, invalid UTF-8, and truncation', () {
      final alias = _alias('alias', 0);
      for (final bytes in [
        _alias('alias', 1),
        _alias('alias', 0xffffffff),
        [255, ...alias.skip(1)],
        alias.sublist(0, alias.length - 1),
      ]) {
        expect(
          () => StarDictSynonyms.parse(bytes, _info(0, 1, synonyms: 1)),
          _formatError,
        );
      }
    });

    test('rejects aliases out of StarDict order', () {
      final bytes = [..._alias('alias', 0), ..._alias('Alias', 0)];
      expect(
        () => StarDictSynonyms.parse(bytes, _info(0, 1, synonyms: 2)),
        _formatError,
      );
    });
  });
}
