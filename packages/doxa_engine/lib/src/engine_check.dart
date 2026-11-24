// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';
import 'package:pdfium_ffi/testing.dart';

/// Result of [runEngineCheck].
final class EngineCheckResult {
  const EngineCheckResult({
    required this.pageCount,
    required this.pageWidth,
    required this.pageHeight,
    required this.text,
    required this.bgraPixels,
    required this.renderWidth,
    required this.renderHeight,
    required this.elapsed,
  });

  final int pageCount;

  /// Page size in PDF points.
  final double pageWidth;
  final double pageHeight;

  /// Text extracted from page 1.
  final String text;

  /// Page 1 rendered as tightly packed BGRA pixels (4 bytes per pixel).
  final Uint8List bgraPixels;
  final int renderWidth;
  final int renderHeight;

  /// Time spent in PDFium, including library initialization.
  final Duration elapsed;
}

/// Temporary M0 diagnostic (issue #4): checks that the bundled PDFium
/// library loads on this device by opening a generated PDF, extracting its
/// text and rendering page 1 at [renderWidth] pixels wide.
///
/// Runs in a short-lived isolate so the UI never blocks. It is replaced by
/// the real engine worker in Spike A (issue #5).
Future<EngineCheckResult> runEngineCheck({int renderWidth = 400}) =>
    Isolate.run(() => _check(renderWidth));

EngineCheckResult _check(int renderWidth) {
  final stopwatch = Stopwatch()..start();
  final pdfium = openPdfium();
  final config = calloc<FPDF_LIBRARY_CONFIG_>()..ref.version = 2;
  pdfium.FPDF_InitLibraryWithConfig(config);
  calloc.free(config);

  final bytes = buildMinimalPdf();
  final buffer = malloc<Uint8>(bytes.length);
  buffer.asTypedList(bytes.length).setAll(0, bytes);
  final doc = pdfium.FPDF_LoadMemDocument64(
    buffer.cast(),
    bytes.length,
    nullptr,
  );
  try {
    if (doc == nullptr) {
      throw StateError('PDFium error ${pdfium.FPDF_GetLastError()}');
    }
    final page = pdfium.FPDF_LoadPage(doc, 0);
    final width = pdfium.FPDF_GetPageWidthF(page);
    final height = pdfium.FPDF_GetPageHeightF(page);

    final textPage = pdfium.FPDFText_LoadPage(page);
    final count = pdfium.FPDFText_CountChars(textPage);
    final utf16 = calloc<UnsignedShort>(count + 1);
    pdfium.FPDFText_GetText(textPage, 0, count, utf16);
    final text = String.fromCharCodes(utf16.cast<Uint16>().asTypedList(count));
    calloc.free(utf16);
    pdfium.FPDFText_ClosePage(textPage);

    final renderHeight = (renderWidth * height / width).round();
    final bitmap = pdfium.FPDFBitmap_Create(renderWidth, renderHeight, 1);
    pdfium.FPDFBitmap_FillRect(
      bitmap,
      0,
      0,
      renderWidth,
      renderHeight,
      0xFFFFFFFF,
    );
    pdfium.FPDF_RenderPageBitmap(
      bitmap,
      page,
      0,
      0,
      renderWidth,
      renderHeight,
      0,
      FPDF_ANNOT | FPDF_LCD_TEXT,
    );
    final stride = pdfium.FPDFBitmap_GetStride(bitmap);
    final src = pdfium.FPDFBitmap_GetBuffer(bitmap)
        .cast<Uint8>()
        .asTypedList(stride * renderHeight);
    final pixels = Uint8List(renderWidth * renderHeight * 4);
    for (var y = 0; y < renderHeight; y++) {
      pixels.setRange(
        y * renderWidth * 4,
        (y + 1) * renderWidth * 4,
        src,
        y * stride,
      );
    }
    pdfium.FPDFBitmap_Destroy(bitmap);
    pdfium.FPDF_ClosePage(page);

    return EngineCheckResult(
      pageCount: pdfium.FPDF_GetPageCount(doc),
      pageWidth: width,
      pageHeight: height,
      text: text,
      bgraPixels: pixels,
      renderWidth: renderWidth,
      renderHeight: renderHeight,
      elapsed: stopwatch.elapsed,
    );
  } finally {
    if (doc != nullptr) pdfium.FPDF_CloseDocument(doc);
    malloc.free(buffer);
    pdfium.FPDF_DestroyLibrary();
  }
}
