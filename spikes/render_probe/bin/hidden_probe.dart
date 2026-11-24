// SPDX-License-Identifier: GPL-3.0-or-later
// Spike A: can a read-only render instance hide Doxa-owned annotations (in
// memory only) so PDFium paints content + foreign annotations, while Flutter
// draws Doxa's own? Throwaway prototype.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';
import 'package:pdfium_ffi/testing.dart';

late final PdfiumBindings pdf;

void main() {
  pdf = openPdfium();
  final config = calloc<FPDF_LIBRARY_CONFIG_>()..ref.version = 2;
  pdf.FPDF_InitLibraryWithConfig(config);
  final bytes = buildMinimalPdf();
  final buf = malloc<Uint8>(bytes.length);
  buf.asTypedList(bytes.length).setAll(0, bytes);
  final doc = pdf.FPDF_LoadMemDocument64(buf.cast(), bytes.length, nullptr);
  final page = pdf.FPDF_LoadPage(doc, 0);

  // Two ink annotations: "doxa-1" (red, left) and "foreign-1" (green, right).
  ink(page, 'doxa-1', 20, 150, (220, 0, 0));
  ink(page, 'foreign-1', 120, 150, (0, 160, 0));

  String probe(String label) {
    final px = renderAnnots(page);
    String at(int x, int y) {
      final i = (y * 200 + x) * 4;
      return px[i] > 200 && px[i + 1] < 60 ? 'red' : px[i + 1] > 120 && px[i] < 60 ? 'green' : 'white';
    }
    return '$label: doxa area=${at(40, 45)} foreign area=${at(140, 45)}';
  }

  print(probe('both visible        '));
  setHidden(page, 'doxa-1', true);
  print(probe('doxa hidden (memory)'));
  setHidden(page, 'doxa-1', false);
  print(probe('doxa shown again    '));

  // Cost of rendering with vs without FPDF_ANNOT on a page with 2 annots.
  final sw = Stopwatch()..start();
  for (var i = 0; i < 200; i++) {
    renderAnnots(page);
  }
  print('render with FPDF_ANNOT: ${(sw.elapsedMicroseconds / 200 / 1000).toStringAsFixed(2)} ms/page (200x200 px)');
  pdf.FPDF_ClosePage(page);
  pdf.FPDF_CloseDocument(doc);
}

void ink(Pointer<fpdf_page_t__> page, String nm, double x, double y, (int, int, int) c) {
  final a = pdf.FPDFPage_CreateAnnot(page, FPDF_ANNOT_INK);
  final r = calloc<FS_RECTF_>();
  r.ref
    ..left = x
    ..right = x + 60
    ..top = y + 10
    ..bottom = y - 10;
  pdf.FPDFAnnot_SetRect(a, r);
  calloc.free(r);
  final k = 'NM'.toNativeUtf8().cast<Char>(), v = nm.toNativeUtf16().cast<UnsignedShort>();
  pdf.FPDFAnnot_SetStringValue(a, k, v);
  calloc
    ..free(k)
    ..free(v);
  pdf.FPDFAnnot_SetFlags(a, FPDF_ANNOT_FLAG_PRINT);
  final path = pdf.FPDFPageObj_CreateNewPath(x, y - 6);
  pdf.FPDFPath_LineTo(path, x + 60, y - 6);
  pdf.FPDFPath_LineTo(path, x + 60, y + 6);
  pdf.FPDFPath_LineTo(path, x, y + 6);
  pdf.FPDFPath_Close(path);
  pdf.FPDFPath_SetDrawMode(path, FPDF_FILLMODE_WINDING, 0);
  pdf.FPDFPageObj_SetFillColor(path, c.$1, c.$2, c.$3, 255);
  pdf.FPDFAnnot_AppendObject(a, path);
  pdf.FPDFPage_CloseAnnot(a);
}

void setHidden(Pointer<fpdf_page_t__> page, String nm, bool hidden) {
  for (var i = 0; i < pdf.FPDFPage_GetAnnotCount(page); i++) {
    final a = pdf.FPDFPage_GetAnnot(page, i);
    final k = 'NM'.toNativeUtf8().cast<Char>();
    final buf = calloc<UnsignedShort>(64);
    final n = pdf.FPDFAnnot_GetStringValue(a, k, buf, 128);
    final name = String.fromCharCodes(buf.cast<Uint16>().asTypedList(n ~/ 2 - 1));
    if (name == nm) {
      final f = pdf.FPDFAnnot_GetFlags(a);
      pdf.FPDFAnnot_SetFlags(a, hidden ? f | FPDF_ANNOT_FLAG_HIDDEN : f & ~FPDF_ANNOT_FLAG_HIDDEN);
    }
    calloc
      ..free(k)
      ..free(buf);
    pdf.FPDFPage_CloseAnnot(a);
  }
}

List<int> renderAnnots(Pointer<fpdf_page_t__> page) {
  final bmp = pdf.FPDFBitmap_Create(200, 200, 1);
  pdf.FPDFBitmap_FillRect(bmp, 0, 0, 200, 200, 0xFFFFFFFF);
  pdf.FPDF_RenderPageBitmap(bmp, page, 0, 0, 200, 200, 0, FPDF_ANNOT | FPDF_REVERSE_BYTE_ORDER);
  final px = List<int>.of(pdf.FPDFBitmap_GetBuffer(bmp).cast<Uint8>().asTypedList(200 * 200 * 4));
  pdf.FPDFBitmap_Destroy(bmp);
  return px;
}
