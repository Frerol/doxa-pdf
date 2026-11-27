// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// Big-endian header: magic/version, source stamps, row count, four section
// positions and a checksum. Each table starts with fixed-size rows containing
// a key offset/length, ordinal with the alias flag, and a row/key checksum.
// The diacritic table also has a projection of its headword rows and ordinals.
const _magic = 0x444f5846; // DOXF
const _version = 1;
const _headerSize = 88;
const _rowSize = 16;
const _projectionSize = 12;
const _aliasFlag = 0x80000000;
const _wordMask = _aliasFlag - 1;

typedef FoldSource = ({int kind, int size, int modified});

FoldSource foldSource(File? file, int kind) {
  final stat = file?.statSync();
  return (
    kind: kind,
    size: stat?.size ?? 0,
    modified: stat?.modified.microsecondsSinceEpoch ?? 0,
  );
}

int _hash(Uint8List bytes, int start, int end, [int hash = 0x811c9dc5]) {
  for (var i = start; i < end; i++) {
    hash = ((hash ^ bytes[i]) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

int _shared(Uint8List a, Uint8List b) {
  final end = min(a.length, b.length);
  var i = 0;
  while (i < end && a[i] == b[i]) {
    i++;
  }
  return i;
}

int _compare(Uint8List a, Uint8List b) {
  final shared = _shared(a, b);
  return shared == min(a.length, b.length)
      ? a.length - b.length
      : a[shared] - b[shared];
}

final class FoldIndex {
  FoldIndex._(
    this._file,
    this._rows,
    this._words,
    this._maxKeyBytes,
    this._caseKeysEnd,
    this._diacriticStart,
    this._diacriticKeysEnd,
    this._projectionStart,
  );

  final RandomAccessFile _file;
  final int _rows;
  final int _words;
  final int _maxKeyBytes;
  final int _caseKeysEnd;
  final int _diacriticStart;
  final int _diacriticKeysEnd;
  final int _projectionStart;

  static FoldIndex? open(
    File file,
    FoldSource idx,
    FoldSource syn,
    int rows,
    int words,
    int maxKeyBytes,
  ) {
    RandomAccessFile? handle;
    try {
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final input = handle = file.openSync();
      final bytes = input.readSync(_headerSize);
      if (bytes.length != _headerSize) return null;
      final header = ByteData.sublistView(bytes);
      if (header.getUint32(0) != _magic ||
          header.getUint32(4) != _version ||
          !_matchesSource(header, 8, idx) ||
          !_matchesSource(header, 28, syn) ||
          header.getUint32(48) != rows ||
          header.getUint32(84) != _hash(bytes, 0, 84)) {
        return null;
      }
      final caseEnd = header.getUint64(52);
      final diacriticStart = header.getUint64(60);
      final diacriticEnd = header.getUint64(68);
      final projection = header.getUint64(76);
      if (caseEnd < _headerSize + rows * _rowSize ||
          diacriticStart != caseEnd ||
          diacriticEnd < diacriticStart + rows * _rowSize ||
          projection != diacriticEnd ||
          projection + words * _projectionSize != input.lengthSync()) {
        return null;
      }
      handle = null;
      return FoldIndex._(
        input,
        rows,
        words,
        maxKeyBytes,
        caseEnd,
        diacriticStart,
        diacriticEnd,
        projection,
      );
    } on FileSystemException {
      return null;
    } finally {
      handle?.closeSync();
    }
  }

  static bool _matchesSource(ByteData header, int offset, FoldSource source) =>
      header.getUint32(offset) == source.kind &&
      header.getInt64(offset + 4) == source.size &&
      header.getInt64(offset + 12) == source.modified;

  Uint8List _read(int offset, int size) {
    final bytes = (_file..setPositionSync(offset)).readSync(size);
    if (bytes.length != size) {
      throw const FormatException('Truncated fold index');
    }
    return bytes;
  }

  ({Uint8List key, int ordinal, bool alias}) _row(int row, bool diacritic) {
    final start = diacritic ? _diacriticStart : _headerSize;
    final end = diacritic ? _diacriticKeysEnd : _caseKeysEnd;
    final bytes = _read(start + row * _rowSize, _rowSize);
    final data = ByteData.sublistView(bytes);
    final offset = data.getUint32(0);
    final length = data.getUint32(4);
    final tagged = data.getUint32(8);
    final ordinal = tagged & _wordMask;
    final keys = start + _rows * _rowSize;
    if (length > _maxKeyBytes ||
        offset > end - keys ||
        length > end - keys - offset ||
        ordinal >= _words) {
      throw const FormatException('Invalid fold index row');
    }
    final key = _read(keys + offset, length);
    if (data.getUint32(12) != _hash(key, 0, length, _hash(bytes, 0, 12))) {
      throw const FormatException('Damaged fold index row');
    }
    return (key: key, ordinal: ordinal, alias: tagged >= _aliasFlag);
  }

  ({int row, int ordinal}) _project(
    Uint8List bytes,
    ByteData data,
    int offset,
  ) {
    final row = data.getUint32(offset);
    final ordinal = data.getUint32(offset + 4);
    if (row >= _rows ||
        ordinal >= _words ||
        data.getUint32(offset + 8) != _hash(bytes, offset, offset + 8)) {
      throw const FormatException('Invalid fold index projection');
    }
    return (row: row, ordinal: ordinal);
  }

  Uint8List _headwordKey(int index) {
    final bytes = _read(
      _projectionStart + index * _projectionSize,
      _projectionSize,
    );
    final projected = _project(bytes, ByteData.sublistView(bytes), 0);
    final word = _row(projected.row, true);
    if (word.alias || word.ordinal != projected.ordinal) {
      throw const FormatException('Invalid projected headword');
    }
    return word.key;
  }

  Set<int> lookup(String folded, {required bool diacritic}) {
    final key = utf8.encode(folded);
    final ordinals = <int>{};
    final first = _lowerBound(
      _rows,
      (i) => _compare(_row(i, diacritic).key, key),
    );
    for (var i = first; i < _rows; i++) {
      final row = _row(i, diacritic);
      if (_compare(row.key, key) != 0) break;
      ordinals.add(row.ordinal);
    }
    return ordinals;
  }

  Iterable<int> suggestions(String folded) sync* {
    final key = utf8.encode(folded);
    if (key.isEmpty) return;
    final insertion = _lowerBound(
      _words,
      (i) => _compare(_headwordKey(i), key),
    );
    var shared = max(
      insertion > 0 ? _shared(_headwordKey(insertion - 1), key) : 0,
      insertion < _words ? _shared(_headwordKey(insertion), key) : 0,
    );
    // Distinct code points can share UTF-8 lead bytes. Keep complete runes.
    while (shared > 0 && shared < key.length && (key[shared] & 0xc0) == 0x80) {
      shared--;
    }
    if (shared == 0) return;
    final prefix = Uint8List.sublistView(key, 0, shared);
    final first = _lowerBound(
      insertion,
      (i) => _compare(_headwordKey(i), prefix),
    );
    final end = _lowerBound(_words, (i) {
      final word = _headwordKey(i);
      return _shared(word, prefix) == shared ? -1 : _compare(word, prefix);
    });
    // The projection omits aliases and lets this range be read sequentially.
    // The caller retains only the requested number of lowest distinct ordinals.
    const blockRows = 1024;
    for (var i = first; i < end; i += blockRows) {
      final length = min(blockRows, end - i) * _projectionSize;
      final bytes = _read(_projectionStart + i * _projectionSize, length);
      final data = ByteData.sublistView(bytes);
      for (var offset = 0; offset < length; offset += _projectionSize) {
        yield _project(bytes, data, offset).ordinal;
      }
    }
  }

  void close() => _file.closeSync();
}

int _lowerBound(int high, int Function(int) compare) {
  var low = 0;
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    if (compare(mid) < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

void writeFoldIndex(
  File file,
  FoldSource idx,
  FoldSource syn,
  int words,
  int rows,
  void Function(void Function(String, int)) visit,
  String Function(String) diacritics,
  bool Function() sourcesUnchanged,
) {
  if (words > _aliasFlag || rows > 0xffffffff) {
    throw const FormatException('Too many fold index rows');
  }
  final temp = file.parent.createTempSync('.fold-');
  try {
    final payload = File('${temp.path}/index.fold');
    final output = payload.openSync(mode: FileMode.write);
    try {
      output.setPositionSync(_headerSize);
      _writeTable(output, words, rows, visit, (s) => s.toLowerCase());
      final diacriticStart = output.positionSync();
      final projection = _writeTable(
        output,
        words,
        rows,
        visit,
        diacritics,
        projectHeadwords: true,
      );
      final header = ByteData(_headerSize)
        ..setUint32(0, _magic)
        ..setUint32(4, _version)
        ..setUint32(48, rows)
        ..setUint64(52, diacriticStart)
        ..setUint64(60, diacriticStart)
        ..setUint64(68, projection)
        ..setUint64(76, projection);
      for (final (offset, source) in [(8, idx), (28, syn)]) {
        header
          ..setUint32(offset, source.kind)
          ..setInt64(offset + 4, source.size)
          ..setInt64(offset + 12, source.modified);
      }
      final bytes = header.buffer.asUint8List();
      header.setUint32(84, _hash(bytes, 0, 84));
      output
        ..setPositionSync(0)
        ..writeFromSync(bytes)
        ..flushSync();
    } finally {
      output.closeSync();
    }
    if (sourcesUnchanged()) payload.renameSync(file.path);
  } finally {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }
}

// Only one normalization level is in memory at a time. Keys live in one byte
// arena and the sort moves 32-bit row numbers, leaving key bytes in place.
int _writeTable(
  RandomAccessFile output,
  int words,
  int rows,
  void Function(void Function(String, int)) visit,
  String Function(String) fold, {
  bool projectHeadwords = false,
}) {
  final starts = Uint32List(rows + 1);
  final order = Uint32List(rows);
  final aliases = Uint32List(rows - words);
  var keys = Uint8List(max(1024, rows * 12));
  var used = 0;
  var i = 0;
  visit((word, ordinal) {
    final key = utf8.encode(fold(word));
    final end = used + key.length;
    if (end > 0xffffffff) throw const FormatException('Fold keys exceed 4 GiB');
    if (end > keys.length) {
      keys = Uint8List(max(end, keys.length + keys.length ~/ 2))
        ..setRange(0, used, keys);
    }
    keys.setRange(used, end, key);
    used = starts[i + 1] = end;
    if (i >= words) aliases[i - words] = ordinal;
    order[i] = i;
    i++;
  });
  order.sort((a, b) {
    var left = starts[a];
    var right = starts[b];
    final leftEnd = starts[a + 1];
    final rightEnd = starts[b + 1];
    while (left < leftEnd && right < rightEnd) {
      final difference = keys[left++] - keys[right++];
      if (difference != 0) return difference;
    }
    return (leftEnd - left) - (rightEnd - right);
  });

  final buffer = Uint8List(64 * 1024);
  final data = ByteData.sublistView(buffer);
  var cursor = 0;
  for (final row in order) {
    final start = starts[row];
    final end = starts[row + 1];
    data
      ..setUint32(cursor, start)
      ..setUint32(cursor + 4, end - start)
      ..setUint32(
        cursor + 8,
        row < words ? row : aliases[row - words] | _aliasFlag,
      )
      ..setUint32(
        cursor + 12,
        _hash(keys, start, end, _hash(buffer, cursor, cursor + 12)),
      );
    cursor += _rowSize;
    if (cursor == buffer.length) {
      output.writeFromSync(buffer);
      cursor = 0;
    }
  }
  output
    ..writeFromSync(buffer, 0, cursor)
    ..writeFromSync(keys, 0, used);
  final projection = output.positionSync();
  if (projectHeadwords) {
    cursor = 0;
    final blockLength = buffer.length ~/ _projectionSize * _projectionSize;
    for (var i = 0; i < rows; i++) {
      if (order[i] >= words) continue;
      data
        ..setUint32(cursor, i)
        ..setUint32(cursor + 4, order[i])
        ..setUint32(cursor + 8, _hash(buffer, cursor, cursor + 8));
      cursor += _projectionSize;
      if (cursor == blockLength) {
        output.writeFromSync(buffer, 0, cursor);
        cursor = 0;
      }
    }
    output.writeFromSync(buffer, 0, cursor);
  }
  return projection;
}
