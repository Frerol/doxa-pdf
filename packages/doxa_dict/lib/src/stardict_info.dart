// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'dictionary_format_exception.dart';

/// Metadata from a StarDict `.ifo` file.
final class StarDictInfo {
  StarDictInfo._({
    required this.version,
    required this.bookName,
    required this.wordCount,
    required this.idxFileSize,
    required this.synWordCount,
    required this.idxOffsetBits,
    required this.sameTypeSequence,
    required this.author,
    required this.email,
    required this.website,
    required this.description,
    required this.date,
    required this.dictType,
    required Map<String, String> extra,
  }) : extra = Map.unmodifiable(extra);

  final String version;
  final String bookName;
  final int wordCount;
  final int idxFileSize;
  final int? synWordCount;
  final int idxOffsetBits;
  final String? sameTypeSequence;
  final String? author;
  final String? email;
  final String? website;
  final String? description;
  final String? date;
  final String? dictType;
  final Map<String, String> extra;

  /// Parses UTF-8 StarDict 2.4.2 or 3.0.0 metadata.
  ///
  /// Throws [DictionaryFormatException] for invalid UTF-8 or invalid metadata,
  /// including duplicate keys, missing required keys, and counts or sizes
  /// that are not non-negative decimal integers.
  static StarDictInfo parse(List<int> bytes) {
    if (bytes.any((byte) => byte < 0 || byte > 255)) {
      throw const DictionaryFormatException('Invalid byte in .ifo file');
    }

    final String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      throw const DictionaryFormatException('Invalid UTF-8 in .ifo file');
    }

    final lines = const LineSplitter().convert(content);
    if (lines.isEmpty || lines.first != "StarDict's dict ifo file") {
      throw const DictionaryFormatException('Missing StarDict .ifo header');
    }

    final fields = <String, String>{};
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;

      final separator = line.indexOf('=');
      if (separator <= 0 || line.substring(0, separator).trim().isEmpty) {
        throw const DictionaryFormatException('Expected a key=value line');
      }

      final key = line.substring(0, separator);
      if (fields.isEmpty && key != 'version') {
        throw const DictionaryFormatException('version must be the first key');
      }
      if (fields.containsKey(key)) {
        throw DictionaryFormatException('Duplicate .ifo key: $key');
      }
      fields[key] = line.substring(separator + 1);
    }

    final version = _takeRequired(fields, 'version');
    if (version != '2.4.2' && version != '3.0.0') {
      throw DictionaryFormatException('Unsupported StarDict version: $version');
    }

    final offsetBits = fields.remove('idxoffsetbits');
    if (offsetBits != null &&
        (version != '3.0.0' || (offsetBits != '32' && offsetBits != '64'))) {
      throw const DictionaryFormatException(
        'idxoffsetbits must be 32 or 64 and requires version 3.0.0',
      );
    }

    final bookName = _takeRequired(fields, 'bookname');
    final wordCount = _parseCount(
      'wordcount',
      _takeRequired(fields, 'wordcount'),
    );
    final idxFileSize = _parseCount(
      'idxfilesize',
      _takeRequired(fields, 'idxfilesize'),
    );
    final synWordCount = fields.remove('synwordcount');

    return StarDictInfo._(
      version: version,
      bookName: bookName,
      wordCount: wordCount,
      idxFileSize: idxFileSize,
      synWordCount: synWordCount == null
          ? null
          : _parseCount('synwordcount', synWordCount),
      idxOffsetBits: offsetBits == '64' ? 64 : 32,
      sameTypeSequence: fields.remove('sametypesequence'),
      author: fields.remove('author'),
      email: fields.remove('email'),
      website: fields.remove('website'),
      description: fields.remove('description'),
      date: fields.remove('date'),
      dictType: fields.remove('dicttype'),
      extra: fields,
    );
  }

  static String _takeRequired(Map<String, String> fields, String key) {
    final value = fields.remove(key);
    if (value == null) {
      throw DictionaryFormatException('Missing required .ifo key: $key');
    }
    return value;
  }

  static int _parseCount(String key, String value) {
    final count = int.tryParse(value, radix: 10);
    if (count == null || !RegExp(r'^[0-9]+$').hasMatch(value)) {
      throw DictionaryFormatException(
        '$key must be a non-negative decimal integer',
      );
    }
    return count;
  }
}
