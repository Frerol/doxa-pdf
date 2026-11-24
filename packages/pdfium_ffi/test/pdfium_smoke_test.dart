// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';
import 'package:pdfium_ffi/testing.dart';
import 'package:test/test.dart';

/// Smoke test for the PDFium binaries pinned in tools/pdfium.lock
/// (issue #4): load the library, open a PDF from memory, read its structure
/// and text, and render page 1.
void main() {
  late PdfiumBindings pdfium;

  setUpAll(() {
    pdfium = openPdfium();
    final config = calloc<FPDF_LIBRARY_CONFIG_>();
    config.ref.version = 2;
    pdfium.FPDF_InitLibraryWithConfig(config);
    calloc.free(config);
  });

  tearDownAll(() => pdfium.FPDF_DestroyLibrary());

  /// Copies [bytes] to native memory, which must stay alive as long as the
  /// document is open, and loads them as a PDF document.
  (Pointer<fpdf_document_t__>, Pointer<Uint8>) loadFromMemory(Uint8List bytes) {
    final buffer = malloc<Uint8>(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    final doc = pdfium.FPDF_LoadMemDocument64(
      buffer.cast(),
      bytes.length,
      nullptr,
    );
    return (doc, buffer);
  }

  test('opens a PDF, reads page size and text, and renders page 1', () {
    final (doc, buffer) = loadFromMemory(buildMinimalPdf());
    addTearDown(() {
      pdfium.FPDF_CloseDocument(doc);
      malloc.free(buffer);
    });

    expect(doc, isNot(nullptr), reason: 'error ${pdfium.FPDF_GetLastError()}');
    expect(pdfium.FPDF_GetPageCount(doc), 1);

    final page = pdfium.FPDF_LoadPage(doc, 0);
    expect(page, isNot(nullptr));
    addTearDown(() => pdfium.FPDF_ClosePage(page));
    expect(pdfium.FPDF_GetPageWidthF(page), minimalPdfPageSize);
    expect(pdfium.FPDF_GetPageHeightF(page), minimalPdfPageSize);

    // Text extraction.
    final textPage = pdfium.FPDFText_LoadPage(page);
    addTearDown(() => pdfium.FPDFText_ClosePage(textPage));
    final count = pdfium.FPDFText_CountChars(textPage);
    expect(count, minimalPdfText.length);
    final utf16 = calloc<UnsignedShort>(count + 1);
    addTearDown(() => calloc.free(utf16));
    pdfium.FPDFText_GetText(textPage, 0, count, utf16);
    expect(
      String.fromCharCodes(utf16.cast<Uint16>().asTypedList(count)),
      minimalPdfText,
    );

    // Render at 1 px per point onto a white BGRx bitmap.
    const size = minimalPdfPageSize;
    final bitmap = pdfium.FPDFBitmap_Create(size, size, 0);
    expect(bitmap, isNot(nullptr));
    addTearDown(() => pdfium.FPDFBitmap_Destroy(bitmap));
    pdfium.FPDFBitmap_FillRect(bitmap, 0, 0, size, size, 0xFFFFFFFF);
    pdfium.FPDF_RenderPageBitmap(bitmap, page, 0, 0, size, size, 0, 0);

    final stride = pdfium.FPDFBitmap_GetStride(bitmap);
    final pixels = pdfium.FPDFBitmap_GetBuffer(bitmap)
        .cast<Uint8>()
        .asTypedList(stride * size);
    int blueAt(int x, int yFromTop) => pixels[yFromTop * stride + x * 4];

    // The square spans x 60..140 and y 20..100 in PDF space (origin at the
    // bottom-left), i.e. rows 100..180 from the top of the bitmap.
    expect(blueAt(100, 140), lessThan(16), reason: 'inside the black square');
    expect(blueAt(5, 195), greaterThan(240), reason: 'blank corner');
  });

  test('reports a format error for data that is not a PDF', () {
    final (doc, buffer) = loadFromMemory(Uint8List.fromList('nope'.codeUnits));
    addTearDown(() => malloc.free(buffer));

    expect(doc, nullptr);
    expect(pdfium.FPDF_GetLastError(), FPDF_ERR_FORMAT);
  });
}
