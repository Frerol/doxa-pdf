// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:test/test.dart';

const _header = "StarDict's dict ifo file";
const _requiredFields = [
  'version=2.4.2',
  'bookname=Test',
  'wordcount=0',
  'idxfilesize=0',
];
const _minimal =
    '$_header\nversion=2.4.2\nbookname=Test\nwordcount=0\nidxfilesize=0';

StarDictInfo _parse(String content) => StarDictInfo.parse(utf8.encode(content));

void main() {
  test('reads all fields and preserves values after the first equals sign', () {
    final info = StarDictInfo.parse(
      File('test/fixtures/full.ifo').readAsBytesSync(),
    );
    expect(info.version, '3.0.0');
    expect(info.bookName, 'Dicionário de teste');
    expect(info.wordCount, 2);
    expect(info.idxFileSize, 36);
    expect(info.synWordCount, 1);
    expect(info.idxOffsetBits, 64);
    expect(info.sameTypeSequence, 'm');
    expect(info.author, 'Test Author');
    expect(info.email, 'test@example.org');
    expect(info.website, 'https://example.org/?lang=pt');
    expect(info.description, '  a=b');
    expect(info.date, '2026-11-25');
    expect(info.dictType, 'example');
    expect(info.extra, {'lang': 'pt', 'custom': ''});
    expect(() => info.extra['lang'] = 'en', throwsUnsupportedError);
  });

  for (final (name, newline) in [
    ('LF', '\n'),
    ('CRLF', '\r\n'),
    ('CR', '\r'),
  ]) {
    test('accepts $name and skips whitespace-only lines after the header', () {
      final info = _parse(
        [_header, '', ' \t', ..._requiredFields, ''].join(newline),
      );
      expect(info.bookName, 'Test');
    });
  }

  for (final version in ['2.4.2', '3.0.0']) {
    test('uses defaults for version $version', () {
      final info = _parse(_minimal.replaceFirst('2.4.2', version));
      expect(info.version, version);
      expect(info.wordCount, 0);
      expect(info.idxFileSize, 0);
      expect(info.idxOffsetBits, 32);
      expect(info.synWordCount, isNull);
      expect(info.sameTypeSequence, isNull);
      expect(info.author, isNull);
      expect(info.email, isNull);
      expect(info.website, isNull);
      expect(info.description, isNull);
      expect(info.date, isNull);
      expect(info.dictType, isNull);
      expect(info.extra, isEmpty);
    });
  }

  test('accepts explicit 32-bit offsets in version 3.0.0', () {
    final info = _parse(
      '$_minimal\nidxoffsetbits=32'.replaceFirst('2.4.2', '3.0.0'),
    );
    expect(info.idxOffsetBits, 32);
  });

  final invalidFormat = throwsA(isA<DictionaryFormatException>());
  for (final (name, bytes) in [
    ('invalid UTF-8 sequence', [0xc3, 0x28]),
    ('truncated UTF-8 sequence', [0xe2, 0x82]),
    ('byte above 255', [256]),
    ('negative byte', [-1]),
  ]) {
    test('rejects $name', () {
      expect(
        () => StarDictInfo.parse([...utf8.encode(_minimal), ...bytes]),
        invalidFormat,
      );
    });
  }

  for (final (name, content) in [
    ('empty input', ''),
    ('incorrect header', _minimal.replaceFirst(_header, 'Invalid header')),
    ('blank line before the header', '\n$_minimal'),
    ('missing version', _header),
    ('version after another key', '$_header\nbookname=Test\nversion=2.4.2'),
    ('unsupported version', _minimal.replaceFirst('2.4.2', '2.4.1')),
    ('line without separator', '$_minimal\ninvalid'),
    ('empty key', '$_minimal\n=value'),
    ('whitespace-only key', '$_minimal\n  =value'),
    ('duplicate known key', '$_minimal\nbookname=Other'),
    ('duplicate unknown key', '$_minimal\nlang=pt\nlang=en'),
    ('32-bit offset declaration in 2.4.2', '$_minimal\nidxoffsetbits=32'),
    ('64-bit offset declaration in 2.4.2', '$_minimal\nidxoffsetbits=64'),
    (
      'unsupported offset width',
      '$_minimal\nidxoffsetbits=16'.replaceFirst('2.4.2', '3.0.0'),
    ),
    (
      'non-integer offset width',
      '$_minimal\nidxoffsetbits=32.0'.replaceFirst('2.4.2', '3.0.0'),
    ),
  ]) {
    test('rejects $name', () {
      expect(() => _parse(content), invalidFormat);
    });
  }

  for (final field in _requiredFields.skip(1)) {
    test('rejects missing ${field.split('=').first}', () {
      expect(
        () => _parse(_minimal.replaceFirst('\n$field', '')),
        invalidFormat,
      );
    });
  }

  for (final key in ['wordcount', 'idxfilesize', 'synwordcount']) {
    for (final value in [
      '',
      'abc',
      '1.5',
      '-1',
      '0x10',
      '9223372036854775808',
    ]) {
      test('rejects invalid $key value "$value"', () {
        final content = key == 'synwordcount'
            ? '$_minimal\n$key=$value'
            : _minimal.replaceFirst('$key=0', '$key=$value');
        expect(() => _parse(content), invalidFormat);
      });
    }
  }
}
