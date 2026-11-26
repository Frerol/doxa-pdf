// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Bytes read from each end of the file.
const identitySampleBytes = 64 * 1024;

/// The identity of a PDF file (docs/plan/03-architecture.md §7): a hash of
/// its size and its first and last [identitySampleBytes]. It survives
/// renames and moves, so the library keeps the reading state.
///
/// The hash is 64-bit FNV-1a, run twice with different offsets, so a
/// personal library has no realistic collision without needing a
/// cryptographic hash package. The trailer, and with it the PDF `/ID`,
/// is inside the last bytes of almost every file.
///
/// Saving annotations into the file (M2) changes these bytes: the saver
/// must update the stored identity of the document it saved.
///
/// Reads the file on another isolate.
Future<String> documentIdentity(String path) =>
    Isolate.run(() => documentIdentitySync(path));

String documentIdentitySync(String path) {
  final file = File(path).openSync();
  try {
    final size = file.lengthSync();
    final headLength = size < identitySampleBytes ? size : identitySampleBytes;
    final head = file.readSync(headLength);
    final tailLength = size - headLength < identitySampleBytes
        ? size - headLength
        : identitySampleBytes;
    file.setPositionSync(size - tailLength);
    final tail = file.readSync(tailLength);
    return identityOf(size, head, tail);
  } finally {
    file.closeSync();
  }
}

/// The identity of a file of [size] bytes that starts with [head] and ends
/// with [tail] (the tail does not overlap the head).
String identityOf(int size, Uint8List head, Uint8List tail) {
  final sizeBytes = ByteData(8)..setUint64(0, size);
  final parts = [sizeBytes.buffer.asUint8List(), head, tail];
  final a = _fnv1a(parts, _fnvOffset);
  final b = _fnv1a(parts, _fnvOffset ^ 0x5bd1e9955bd1e995);
  return 'v1-${_hex(a)}${_hex(b)}-$size';
}

const _fnvOffset = 0xcbf29ce484222325;
const _fnvPrime = 0x100000001b3;

int _fnv1a(List<Uint8List> parts, int seed) {
  var hash = seed;
  for (final part in parts) {
    for (final byte in part) {
      hash = (hash ^ byte) * _fnvPrime;
    }
  }
  return hash;
}

String _hex(int value) =>
    (value.toUnsigned(64)).toRadixString(16).padLeft(16, '0');
