// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:test/test.dart';

void main() {
  for (final (sequence, offset, size, types) in [
    (null, 0, 16, ['m', 'W']),
    ('mW', 16, 10, ['m', 'W']),
    ('Wm', 26, 13, ['W', 'm']),
  ]) {
    test('reads mixed fields with sequence $sequence', () {
      final reader = DictionaryData.openDictzip(
        File('test/fixtures/mixed.dict.dz'),
      );
      addTearDown(reader.close);
      final fields = DictionaryField.parse(
        reader.read(offset, size),
        sameTypeSequence: sequence,
      );
      expect(fields.map((field) => field.type), types);
      final text = fields.singleWhere((field) => field.type == 'm');
      expect(text.bytes, [0x61, 0xc3, 0xa7, 0xc3, 0xa3, 0x6f]);
      expect(text.text, 'ação');
      final binary = fields.singleWhere((field) => field.type == 'W');
      expect(binary.bytes, [0, 255, 16]);
      expect(binary.text, isNull);
    });
  }

  test(
    'allows an empty final text or binary field and zero-length framing',
    () {
      for (final type in ['m', 'W']) {
        final fields = DictionaryField.parse(
          Uint8List(0),
          sameTypeSequence: type,
        );
        expect(fields.single.bytes, isEmpty);
        expect(fields.single.text, type == 'm' ? '' : null);
      }
      final fields = DictionaryField.parse(
        Uint8List.fromList([0x6d, 0, 0x57, 0, 0, 0, 0]),
      );
      expect(fields.map((field) => field.bytes), everyElement(isEmpty));
    },
  );

  final malformed = <String, (List<int>, String?)>{
    'invalid explicit type': ([0x32], null),
    'invalid implicit type': ([], 'é'),
    'empty sequence': ([], ''),
    'missing text terminator': ([0x6d, 0x61], null),
    'short binary prefix': ([0x57, 0], null),
    'short binary payload': ([0x57, 0, 0, 0, 1], null),
    'unsigned oversized binary length': ([0xff, 0xff, 0xff, 0xff], 'Wm'),
    'invalid UTF-8': ([0x6d, 0xff, 0], null),
    'invalid UTF-8 in final field': ([0xc3], 'm'),
  };
  for (final MapEntry(key: name, value: (bytes, sequence))
      in malformed.entries) {
    test('rejects $name', () {
      expect(
        () => DictionaryField.parse(
          Uint8List.fromList(bytes),
          sameTypeSequence: sequence,
        ),
        throwsA(isA<DictionaryFormatException>()),
      );
    });
  }
}
