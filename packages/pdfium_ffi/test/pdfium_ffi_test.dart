// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:pdfium_ffi/pdfium_ffi.dart' as pdfium_ffi;
import 'package:test/test.dart';

void main() {
  test('library loads', () {
    expect(pdfium_ffi.packageName, 'pdfium_ffi');
  });
}
