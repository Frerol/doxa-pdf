// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'dictionary_format_exception.dart';
import 'stardict_info.dart';

/// A headword and its definition's byte range in the dictionary data.
typedef StarDictIndexEntry = ({String headword, int offset, int size});

/// A validated StarDict `.idx` or `.idx.gz` file in ordinal order.
final class StarDictIndex {
  StarDictIndex._(this._table, this._offsetBytes);

  /// Maximum decompressed size accepted for a gzip index (128 MiB).
  static const maxGzipIndexSize = 128 * 1024 * 1024;

  // GZipCodec may return all decoded bytes even if the final trailer is
  // truncated. A following member must decode independently to prove that
  // the preceding member ended.
  static final _endProbe = GZipCodec().encode(const [0x5a]);

  final _WordTable _table;
  final int _offsetBytes;

  /// Parses index bytes using the size, count and offset width from [info].
  ///
  /// 64-bit offsets at or above 2^63 are rejected: no dictionary file can be
  /// that large, and offsets stay plain Dart [int]s.
  static StarDictIndex parse(
    List<int> bytes,
    StarDictInfo info, {
    bool gzip = false,
  }) {
    if (!gzip && bytes.length != info.idxFileSize) {
      throw const DictionaryFormatException('Incorrect .idx byte count');
    }

    final input = _copyBytes(bytes, gzip ? '.idx.gz' : '.idx');
    final data = gzip ? _inflate(input, info.idxFileSize) : input;
    final offsetBytes = info.idxOffsetBits ~/ 8;
    final table = _WordTable.parse(
      data,
      info.wordCount,
      offsetBytes + 4,
      '.idx',
    );
    if (offsetBytes == 8) {
      for (var i = 0; i < table.length; i++) {
        if (table.data.getUint32(table.wordEnd(i) + 1) >= 0x80000000) {
          throw DictionaryFormatException('Unsupported .idx offset at $i');
        }
      }
    }
    return StarDictIndex._(table, offsetBytes);
  }

  int get length => _table.length;

  /// Returns the entry at a zero-based ordinal.
  StarDictIndexEntry operator [](int ordinal) {
    final payload = _table.wordEnd(ordinal) + 1;
    final data = _table.data;
    final first = data.getUint32(payload);
    // Parsing rejects 64-bit offsets at or above 2^63, so this cannot overflow.
    final offset = _offsetBytes == 4
        ? first
        : (first << 32) | data.getUint32(payload + 4);
    return (
      headword: _table.wordAt(ordinal),
      offset: offset,
      size: data.getUint32(payload + _offsetBytes),
    );
  }

  /// Returns all matching ordinals in file order, including duplicates.
  /// Set [ignoreAsciiCase] to match ASCII upper- and lowercase alike.
  List<int> lookup(String headword, {bool ignoreAsciiCase = false}) =>
      _table.lookup(headword, ignoreAsciiCase: ignoreAsciiCase);

  static Uint8List _inflate(Uint8List bytes, int expectedSize) {
    if (expectedSize > maxGzipIndexSize) {
      throw const DictionaryFormatException('Decompressed .idx exceeds limit');
    }

    if (bytes.length < 18 || bytes[0] != 0x1f || bytes[1] != 0x8b) {
      throw const DictionaryFormatException(
        'Missing .idx.gz header or trailer',
      );
    }

    final output = _BoundedOutput(expectedSize);
    try {
      final decoder = GZipCodec().decoder.startChunkedConversion(output);
      decoder.add(bytes);
      if (output.length != expectedSize) {
        throw const DictionaryFormatException('Incorrect .idx byte count');
      }

      output.checkingEnd = true;
      decoder.add(_endProbe);
      decoder.close();
      if (!output.reachedEnd) {
        throw const DictionaryFormatException('Truncated .idx.gz stream');
      }
    } on DictionaryFormatException {
      rethrow;
    } on FormatException {
      throw const DictionaryFormatException('Invalid .idx.gz stream');
    }
    return output.bytes.takeBytes();
  }
}

/// A validated StarDict `.syn` file mapping aliases to index ordinals.
final class StarDictSynonyms {
  StarDictSynonyms._(this._table);

  final _WordTable _table;

  /// Parses a present synonym file. Its count is required in [info].
  ///
  /// With [gzip], [bytes] is a gzip or dictzip `.syn.dz`, as some writers
  /// (PyGlossary) produce. The `.ifo` gives no size for it, so it may
  /// decompress to at most [StarDictIndex.maxGzipIndexSize] bytes.
  static StarDictSynonyms parse(
    List<int> bytes,
    StarDictInfo info, {
    bool gzip = false,
  }) {
    final count = info.synWordCount;
    if (count == null) {
      throw const DictionaryFormatException('Missing synwordcount for .syn');
    }

    final copied = _copyBytes(bytes, '.syn');
    final table = _WordTable.parse(
      gzip ? _inflateSynonyms(copied) : copied,
      count,
      4,
      '.syn',
    );
    final synonyms = StarDictSynonyms._(table);
    for (var i = 0; i < count; i++) {
      if (synonyms.ordinalAt(i) >= info.wordCount) {
        throw DictionaryFormatException('Out-of-range .syn ordinal at $i');
      }
    }
    return synonyms;
  }

  int get length => _table.length;

  String aliasAt(int index) => _table.wordAt(index);

  int ordinalAt(int index) => _table.data.getUint32(_table.wordEnd(index) + 1);

  /// Returns the target ordinals of all matching aliases in synonym file order.
  /// Set [ignoreAsciiCase] to match ASCII upper- and lowercase alike.
  List<int> lookup(String alias, {bool ignoreAsciiCase = false}) => _table
      .lookup(alias, ignoreAsciiCase: ignoreAsciiCase)
      .map(ordinalAt)
      .toList();
}

Uint8List _inflateSynonyms(Uint8List bytes) {
  if (bytes.length < 18 || bytes[0] != 0x1f || bytes[1] != 0x8b) {
    throw const DictionaryFormatException('Missing .syn.dz header or trailer');
  }
  final output = _BoundedOutput(StarDictIndex.maxGzipIndexSize);
  try {
    final decoder = GZipCodec().decoder.startChunkedConversion(output);
    decoder.add(bytes);
    // A complete stream lets a second gzip member decode after it; a cut
    // one reads that member as its own missing bytes.
    output.checkingEnd = true;
    decoder
      ..add(StarDictIndex._endProbe)
      ..close();
    if (!output.reachedEnd) {
      throw const DictionaryFormatException('Truncated .syn.dz stream');
    }
  } on DictionaryFormatException {
    rethrow;
  } on FormatException {
    throw const DictionaryFormatException('Invalid .syn.dz stream');
  }
  return output.bytes.takeBytes();
}

Uint8List _copyBytes(List<int> bytes, String file) {
  if (bytes.any((byte) => byte < 0 || byte > 255)) {
    throw DictionaryFormatException('Invalid byte in $file file');
  }
  return Uint8List.fromList(bytes);
}

final class _BoundedOutput implements Sink<List<int>> {
  _BoundedOutput(this.limit);

  final int limit;
  final bytes = BytesBuilder(copy: false);
  int get length => bytes.length;
  bool checkingEnd = false;
  bool reachedEnd = false;

  @override
  void add(List<int> chunk) {
    if (checkingEnd) {
      if (reachedEnd || chunk.length != 1 || chunk.single != 0x5a) {
        throw const DictionaryFormatException('Invalid .idx.gz ending');
      }
      reachedEnd = true;
      return;
    }
    if (chunk.length > limit - length) {
      throw const DictionaryFormatException('Decompressed .idx exceeds size');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}

final class _WordTable {
  _WordTable(this._bytes, this._starts, this._payloadBytes)
    : data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final Uint32List _starts;
  final int _payloadBytes;
  final ByteData data;

  int get length => _starts.length;

  static _WordTable parse(
    Uint8List bytes,
    int count,
    int payloadBytes,
    String file,
  ) {
    if (bytes.length > 0xffffffff ||
        count > bytes.length ~/ (payloadBytes + 1)) {
      throw DictionaryFormatException('Invalid $file size or entry count');
    }

    final starts = Uint32List(count);
    var start = 0;
    var previousEnd = 0;
    for (var i = 0; i < count; i++) {
      final end = bytes.indexOf(0, start);
      if (end < 0 || bytes.length - end - 1 < payloadBytes) {
        throw DictionaryFormatException('Truncated $file entry at $i');
      }
      try {
        const Utf8Decoder().convert(bytes, start, end);
      } on FormatException {
        throw DictionaryFormatException('Invalid UTF-8 in $file entry at $i');
      }

      if (i > 0 &&
          _compare(bytes, starts[i - 1], previousEnd, bytes, start, end) > 0) {
        throw DictionaryFormatException('Unsorted $file entry at $i');
      }
      starts[i] = start;
      previousEnd = end;
      start = end + 1 + payloadBytes;
    }

    if (start != bytes.length) {
      throw DictionaryFormatException('Incorrect $file entry count');
    }
    return _WordTable(bytes, starts, payloadBytes);
  }

  int wordEnd(int ordinal) {
    RangeError.checkValidIndex(ordinal, _starts, 'ordinal');
    final next = ordinal + 1 == length ? _bytes.length : _starts[ordinal + 1];
    return next - 1 - _payloadBytes;
  }

  String wordAt(int ordinal) {
    final end = wordEnd(ordinal);
    final start = _starts[ordinal];
    final word = const Utf8Decoder().convert(_bytes, start, end);
    // Dart's decoder skips an initial BOM. Within the index it is word data.
    if (end - start >= 3 &&
        _bytes[start] == 0xef &&
        _bytes[start + 1] == 0xbb &&
        _bytes[start + 2] == 0xbf) {
      return '\uFEFF$word';
    }
    return word;
  }

  List<int> lookup(String word, {required bool ignoreAsciiCase}) {
    final key = utf8.encode(word);
    var low = 0;
    var high = length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (_compareKey(mid, key, ignoreAsciiCase) < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }

    final matches = <int>[];
    for (var i = low; i < length; i++) {
      if (_compareKey(i, key, ignoreAsciiCase) != 0) break;
      matches.add(i);
    }
    return matches;
  }

  int _compareKey(int ordinal, List<int> key, bool ignoreAsciiCase) => _compare(
    _bytes,
    _starts[ordinal],
    wordEnd(ordinal),
    key,
    0,
    key.length,
    ignoreAsciiCase: ignoreAsciiCase,
  );

  static int _compare(
    List<int> left,
    int leftStart,
    int leftEnd,
    List<int> right,
    int rightStart,
    int rightEnd, {
    bool ignoreAsciiCase = false,
  }) {
    var rawDifference = 0;
    while (leftStart < leftEnd && rightStart < rightEnd) {
      final a = left[leftStart++];
      final b = right[rightStart++];
      final folded = _asciiLower(a) - _asciiLower(b);
      if (folded != 0) return folded;
      if (rawDifference == 0) rawDifference = a - b;
    }

    final remaining = (leftEnd - leftStart) - (rightEnd - rightStart);
    if (remaining != 0) return remaining;
    return ignoreAsciiCase ? 0 : rawDifference;
  }

  static int _asciiLower(int byte) =>
      byte >= 0x41 && byte <= 0x5a ? byte + 0x20 : byte;
}
