// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';
import 'package:test/test.dart';

/// Guards against ffigen emitting library-private (`_`-prefixed) types,
/// which made structs such as FS_QUADPOINTSF unusable outside this package.
void main() {
  test('geometry structs used by the annotation API are public', () {
    final quad = calloc<FS_QUADPOINTSF>();
    final rect = calloc<FS_RECTF_>();
    final matrix = calloc<FS_MATRIX_>();
    addTearDown(() {
      calloc.free(quad);
      calloc.free(rect);
      calloc.free(matrix);
    });
    quad.ref
      ..x1 = 1
      ..y4 = 4;
    rect.ref.left = 2;
    matrix.ref.a = 1;
    expect(quad.ref.x1 + quad.ref.y4 + rect.ref.left + matrix.ref.a, 8);
    expect(sizeOf<FS_QUADPOINTSF>(), 8 * sizeOf<Float>());
  });
}
