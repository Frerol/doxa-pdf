// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'dictionary_format_exception.dart';

/// Synchronous random access to the uncompressed bytes of a StarDict data file.
///
/// The caller owns the reader and must call [close] when finished.
sealed class DictionaryData {
  DictionaryData._(this._file, this.length);

  /// Opens a plain .dict file.
  factory DictionaryData.openPlain(File file) {
    final handle = file.openSync();
    try {
      return _PlainData(handle, handle.lengthSync());
    } on Object {
      handle.closeSync();
      rethrow;
    }
  }

  /// Opens a single-member dictzip .dict.dz file.
  factory DictionaryData.openDictzip(File file) {
    final handle = file.openSync();
    try {
      return _DictzipData.open(handle);
    } on Object {
      handle.closeSync();
      rethrow;
    }
  }

  final RandomAccessFile _file;

  /// Uncompressed size in bytes.
  final int length;

  /// Returns an independent copy of the requested range.
  Uint8List read(int offset, int size) {
    if (offset < 0 || size < 0 || offset > length || size > length - offset) {
      throw const DictionaryFormatException('Dictionary data range is invalid');
    }
    return _read(offset, size);
  }

  Uint8List _read(int offset, int size);

  void close() => _file.closeSync();
}

final class _PlainData extends DictionaryData {
  _PlainData(super.file, super.length) : super._();

  @override
  Uint8List _read(int offset, int size) {
    _file.setPositionSync(offset);
    return _readExactly(_file, size);
  }
}

final class _DictzipData extends DictionaryData {
  _DictzipData(
    super.file,
    super.length,
    this._chunkLength,
    this._offsets,
    this._separateTerminator,
  ) : super._();

  factory _DictzipData.open(RandomAccessFile file) {
    final trailerOffset = file.lengthSync() - 8;
    final header = _readExactly(file, 10);
    final flags = header[3];
    if (header[0] != 0x1f ||
        header[1] != 0x8b ||
        header[2] != 8 ||
        (flags & 0xe0) != 0 ||
        (flags & 4) == 0) {
      throw const DictionaryFormatException('Invalid dictzip gzip header');
    }

    final extraLength = ByteData.sublistView(_readExactly(file, 2))
        .getUint16(0, Endian.little);
    final extra = ByteData.sublistView(_readExactly(file, extraLength));
    ByteData? table;
    var position = 0;
    while (position < extraLength) {
      if (extraLength - position < 4) {
        throw const DictionaryFormatException('Truncated gzip extra subfield');
      }
      final size = extra.getUint16(position + 2, Endian.little);
      final end = position + 4 + size;
      if (end > extraLength) {
        throw const DictionaryFormatException('Truncated gzip extra subfield');
      }
      if (extra.getUint16(position) == 0x5241) {
        if (table != null) {
          throw const DictionaryFormatException('Duplicate dictzip RA table');
        }
        table = ByteData.sublistView(extra, position + 4, end);
      }
      position = end;
    }

    if (table == null ||
        table.lengthInBytes < 6 ||
        table.getUint16(0, Endian.little) != 1) {
      throw const DictionaryFormatException(
        'Missing or invalid dictzip RA table',
      );
    }
    final chunkLength = table.getUint16(2, Endian.little);
    final count = table.getUint16(4, Endian.little);
    if (chunkLength == 0 || table.lengthInBytes != 6 + 2 * count) {
      throw const DictionaryFormatException('Invalid dictzip RA table size');
    }

    final offsets = <int>[0];
    for (var index = 0; index < count; index++) {
      final size = table.getUint16(6 + 2 * index, Endian.little);
      if (size == 0) {
        throw const DictionaryFormatException('Empty compressed dictzip chunk');
      }
      offsets.add(offsets.last + size);
    }

    final headerLimit = trailerOffset - offsets.last;
    if (file.positionSync() > headerLimit) {
      throw const DictionaryFormatException(
        'Dictzip chunks extend past the file',
      );
    }
    for (final flag in [8, 16]) {
      if ((flags & flag) != 0) {
        _skipHeaderString(file, headerLimit);
      }
    }
    if ((flags & 2) != 0) {
      final checksumOffset = file.positionSync();
      if (headerLimit - checksumOffset < 2) {
        throw const DictionaryFormatException('Truncated gzip header checksum');
      }
      final stored = ByteData.sublistView(_readExactly(file, 2))
          .getUint16(0, Endian.little);
      if (stored != _headerChecksum(file, checksumOffset)) {
        throw const DictionaryFormatException('Invalid gzip header checksum');
      }
      file.setPositionSync(checksumOffset + 2);
    }

    final dataStart = file.positionSync();
    final dataEnd = dataStart + offsets.last;
    final tailLength = trailerOffset - dataEnd;
    // dictzip writes Z_FINISH after recording the Z_FULL_FLUSH chunk sizes.
    // Some writers include the final DEFLATE block in the last chunk instead.
    file.setPositionSync(dataEnd);
    if (tailLength != 0 &&
        (tailLength != 2 ||
            ByteData.sublistView(_readExactly(file, 2)).getUint16(0) !=
                0x0300)) {
      throw const DictionaryFormatException(
        'Invalid dictzip compressed data size',
      );
    }
    if (count == 0 && tailLength == 0) {
      throw const DictionaryFormatException('Missing dictzip DEFLATE stream');
    }

    final trailer = ByteData.sublistView(_readExactly(file, 8));
    final length = trailer.getUint32(4, Endian.little);
    final expectedCount = (length + chunkLength - 1) ~/ chunkLength;
    if (count != expectedCount) {
      throw const DictionaryFormatException(
        'Invalid dictzip uncompressed size',
      );
    }
    for (var index = 0; index < offsets.length; index++) {
      offsets[index] += dataStart;
    }
    return _DictzipData(file, length, chunkLength, offsets, tailLength == 2);
  }

  final int _chunkLength;
  final List<int> _offsets;
  final bool _separateTerminator;
  final _cache = <int, Uint8List>{};
  static const _cacheCapacity = 4;

  @override
  Uint8List _read(int offset, int size) {
    final result = Uint8List(size);
    var written = 0;
    while (written < size) {
      final position = offset + written;
      final chunk = _chunk(position ~/ _chunkLength);
      final start = position % _chunkLength;
      final available = chunk.length - start;
      final remaining = size - written;
      final count = available < remaining ? available : remaining;
      result.setRange(written, written + count, chunk, start);
      written += count;
    }
    return result;
  }

  Uint8List _chunk(int index) {
    final cached = _cache.remove(index);
    if (cached != null) {
      _cache[index] = cached;
      return cached;
    }

    final start = _offsets[index];
    final last = index == _offsets.length - 2;
    _file.setPositionSync(start);
    final compressed = _readExactly(_file, _offsets[index + 1] - start);
    final endsWithFlush =
        compressed.length >= 4 &&
        ByteData.sublistView(compressed).getUint32(compressed.length - 4) ==
            0xffff;
    if (endsWithFlush != (!last || _separateTerminator)) {
      throw const DictionaryFormatException('Invalid dictzip chunk boundary');
    }
    final expected = last ? length - index * _chunkLength : _chunkLength;
    final output = _ChunkOutput(expected);
    try {
      final input = ZLibDecoder(raw: true).startChunkedConversion(output);
      input.add(compressed);
      input.close();
    } on FormatException catch (error) {
      throw DictionaryFormatException(
        'Invalid dictzip chunk: ${error.message}',
      );
    }
    if (output.written != expected) {
      throw const DictionaryFormatException(
        'Wrong inflated dictzip chunk size',
      );
    }
    if (_cache.length == _cacheCapacity) _cache.remove(_cache.keys.first);
    return _cache[index] = output.bytes;
  }

  @override
  void close() {
    _cache.clear();
    super.close();
  }
}

Uint8List _readExactly(RandomAccessFile file, int size) {
  final bytes = file.readSync(size);
  if (bytes.length != size) {
    throw const DictionaryFormatException('Truncated dictionary data');
  }
  return bytes;
}

void _skipHeaderString(RandomAccessFile file, int limit) {
  var position = file.positionSync();
  while (position < limit) {
    final remaining = limit - position;
    final bytes = _readExactly(file, remaining < 4096 ? remaining : 4096);
    final terminator = bytes.indexOf(0);
    if (terminator >= 0) {
      file.setPositionSync(position + terminator + 1);
      return;
    }
    position += bytes.length;
  }
  throw const DictionaryFormatException('Unterminated gzip header string');
}

int _headerChecksum(RandomAccessFile file, int length) {
  file.setPositionSync(0);
  var crc = 0xffffffff;
  while (length > 0) {
    final bytes = _readExactly(file, length < 4096 ? length : 4096);
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320);
      }
    }
    length -= bytes.length;
  }
  return (crc ^ 0xffffffff) & 0xffff;
}

final class _ChunkOutput implements Sink<List<int>> {
  _ChunkOutput(int size) : bytes = Uint8List(size);

  final Uint8List bytes;
  int written = 0;

  @override
  void add(List<int> data) {
    if (data.length > bytes.length - written) {
      throw const DictionaryFormatException(
        'Wrong inflated dictzip chunk size',
      );
    }
    bytes.setRange(written, written + data.length, data);
    written += data.length;
  }

  @override
  void close() {}
}
