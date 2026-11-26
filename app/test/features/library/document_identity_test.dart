// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:doxa_pdf/features/library/document_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('doxa_identity'));
  tearDown(() => dir.deleteSync(recursive: true));

  Uint8List bytes(int length) =>
      Uint8List.fromList(List.generate(length, (i) => (i * 31 + 7) & 0xff));

  String identityOfBytes(Uint8List data, [String name = 'a.pdf']) {
    final file = File('${dir.path}/$name')..writeAsBytesSync(data);
    return documentIdentitySync(file.path);
  }

  group('document identity', () {
    test('survives a rename or move: it depends only on the bytes', () {
      final data = bytes(300 * 1024);
      Directory('${dir.path}/moved').createSync();
      expect(identityOfBytes(data, 'moved/renamed.pdf'), identityOfBytes(data));
    });

    test('changes with a byte in the head, in the tail, or the size', () {
      final data = bytes(300 * 1024);
      final original = identityOfBytes(data);
      final head = Uint8List.fromList(data)..[10] ^= 1;
      final tail = Uint8List.fromList(data)..[data.length - 10] ^= 1;
      final longer = Uint8List.fromList([...data, 0]);
      expect({
        original,
        identityOfBytes(head, 'h.pdf'),
        identityOfBytes(tail, 't.pdf'),
        identityOfBytes(longer, 'l.pdf'),
      }, hasLength(4));
    });

    test('ignores the middle of large files', () {
      final data = bytes(300 * 1024);
      final middle = Uint8List.fromList(data)..[150 * 1024] ^= 1;
      expect(identityOfBytes(middle, 'm.pdf'), identityOfBytes(data));
    });

    test('reads small files whole, without the tail overlapping the head', () {
      // Between one and two samples long, the tail is what follows the
      // head; a change in that part must still count.
      for (final length in [10, identitySampleBytes + 100]) {
        final data = bytes(length);
        final changed = Uint8List.fromList(data)..[length - 1] ^= 1;
        expect(
          identityOfBytes(changed, 'c$length.pdf'),
          isNot(identityOfBytes(data, 'o$length.pdf')),
        );
      }
      expect(identityOfBytes(Uint8List(0), 'empty.pdf'), isNotEmpty);
    });
  });
}
