// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:test/test.dart';

const _plain = 'test/fixtures/mixed.dict';
const _dictzip = 'test/fixtures/mixed.dict.dz';
const _extended = 'test/fixtures/mixed-header.dict.dz';
final _formatError = throwsA(isA<DictionaryFormatException>());

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory('test').createTempSync('dictzip-test-');
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  File write(List<int> bytes) =>
      File('${scratch.path}/mutated.dz')..writeAsBytesSync(bytes);

  for (final path in [_dictzip, _extended]) {
    test('reads arbitrary ranges from $path', () {
      final plain = DictionaryData.openPlain(File(_plain));
      addTearDown(plain.close);
      final compressed = DictionaryData.openDictzip(File(path));
      addTearDown(compressed.close);
      expect(compressed.length, plain.length);
      // Covers single chunks, chunk boundaries, the short final chunk and EOF.
      for (var start = plain.length; start >= 0; start--) {
        for (var size = 0; size <= plain.length - start; size++) {
          expect(compressed.read(start, size), plain.read(start, size));
        }
      }
      compressed.read(0, 2)[0] = 0;
      expect(compressed.read(0, 2), plain.read(0, 2));
    });
  }

  test('range errors are typed for both formats', () {
    for (final data in [
      DictionaryData.openPlain(File(_plain)),
      DictionaryData.openDictzip(File(_dictzip)),
    ]) {
      addTearDown(data.close);
      expect(() => data.read(-1, 1), _formatError);
      expect(() => data.read(0, -1), _formatError);
      expect(() => data.read(data.length, 1), _formatError);
      expect(() => data.read(data.length + 1, 0), _formatError);
      expect(() => data.read(1, 0x7fffffffffffffff), _formatError);
    }
  });

  final badHeaders = <String, (int, int)>{
    'magic': (0, 0),
    'compression method': (2, 0),
    'missing FEXTRA': (3, 0),
    'reserved flags': (3, 0x24),
    'unterminated filename': (3, 0x0c),
    'extra length': (10, 0xff),
    'missing RA': (12, 0x58),
    'RA subfield length': (14, 0xff),
    'RA version': (16, 2),
    'nominal chunk length': (18, 0),
    'chunk count': (20, 0),
    'zero compressed chunk size': (22, 0),
    'oversized compressed chunk': (22, 0xff),
  };
  for (final MapEntry(key: name, value: (offset, value))
      in badHeaders.entries) {
    test('rejects invalid $name', () {
      final bytes = File(_dictzip).readAsBytesSync()..[offset] = value;
      expect(() => DictionaryData.openDictzip(write(bytes)), _formatError);
    });
  }

  test('rejects invalid gzip header checksum', () {
    final bytes = File(_extended).readAsBytesSync()..[4] = 1;
    expect(() => DictionaryData.openDictzip(write(bytes)), _formatError);
  });

  test('rejects truncated gzip header and trailer', () {
    final bytes = File(_dictzip).readAsBytesSync();
    for (final length in [0, 9, 11, 19, bytes.length - 1]) {
      expect(
        () => DictionaryData.openDictzip(write(bytes.sublist(0, length))),
        _formatError,
      );
    }
  });

  test('rejects trailer size inconsistent with chunk count', () {
    final bytes = File(_dictzip).readAsBytesSync();
    bytes[bytes.length - 4] = 1;
    expect(() => DictionaryData.openDictzip(write(bytes)), _formatError);
  });

  test('checks inflated length of last chunk against ISIZE', () {
    for (final change in [-1, 1]) {
      final bytes = File(_dictzip).readAsBytesSync();
      bytes[bytes.length - 4] += change;
      final data = DictionaryData.openDictzip(write(bytes));
      try {
        expect(data.read(0, 1), [0x6d]);
        expect(() => data.read(32, 1), _formatError);
      } finally {
        data.close();
      }
    }
  });

  test('checks the inflated length of an interior chunk', () {
    for (final chunkLength in [7, 9]) {
      final bytes = File(_dictzip).readAsBytesSync()..[18] = chunkLength;
      if (chunkLength == 7) {
        bytes[bytes.length - 4] = 35; // Keep the declared chunk count at five.
      }
      final data = DictionaryData.openDictzip(write(bytes));
      try {
        expect(() => data.read(0, 1), _formatError);
      } finally {
        data.close();
      }
    }
  });

  test('accepts a DEFLATE terminator counted in the final RA chunk', () {
    final bytes = File(_dictzip).readAsBytesSync()..[30] += 2;
    final data = DictionaryData.openDictzip(write(bytes));
    addTearDown(data.close);
    expect(data.read(0, data.length), File(_plain).readAsBytesSync());
  });

  test('rejects a missing DEFLATE terminator', () {
    final bytes = File(_dictzip).readAsBytesSync();
    final truncated = [
      ...bytes.take(bytes.length - 10),
      ...bytes.skip(bytes.length - 8),
    ];
    final data = DictionaryData.openDictzip(write(truncated));
    addTearDown(data.close);
    expect(() => data.read(32, 1), _formatError);
  });

  test('rejects an invalid chunk lazily', () {
    final bytes = File(_dictzip).readAsBytesSync();
    final header = ByteData.sublistView(bytes);
    final start = 12 + header.getUint16(10, Endian.little);
    bytes[start] = 0x07; // Reserved DEFLATE block type.
    final data = DictionaryData.openDictzip(write(bytes));
    addTearDown(data.close);
    expect(data.read(8, 1), [0x57]);
    expect(() => data.read(0, 1), _formatError);
  });

  test('rejects an RA chunk boundary shifted within the payload', () {
    final bytes = File(_dictzip).readAsBytesSync()
      ..[22] += 1
      ..[24] -= 1;
    final data = DictionaryData.openDictzip(write(bytes));
    addTearDown(data.close);
    expect(() => data.read(0, 1), _formatError);
  });
}
