// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_engine/doxa_engine.dart';
import 'package:pdfium_ffi/testing.dart';
import 'package:test/test.dart';

void main() {
  test('engine check opens, reads and renders the sample PDF', () async {
    final result = await runEngineCheck(renderWidth: 300);

    expect(result.pageCount, 1);
    expect(result.pageWidth, minimalPdfPageSize);
    expect(result.text, minimalPdfText);
    expect(result.renderHeight, 300);
    expect(result.bgraPixels.length, 300 * 300 * 4);
    // Centre of the black square (PDF 100,60 → 150,210 px from top-left).
    const i = (210 * 300 + 150) * 4;
    expect(result.bgraPixels.sublist(i, i + 3), everyElement(lessThan(16)));
  });
}
