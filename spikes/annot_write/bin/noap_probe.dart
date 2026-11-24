// SPDX-License-Identifier: GPL-3.0-or-later
// Markups saved WITHOUT /AP: how does each reader show them? (Spike C probe)
import 'dart:ffi';
import 'dart:io';

import 'package:annot_write/test_pdfs.dart';
import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

import 'annot_write.dart' as w;

void main(List<String> args) {
  w.pdf = openPdfium();
  final config = calloc<FPDF_LIBRARY_CONFIG_>()..ref.version = 2;
  w.pdf.FPDF_InitLibraryWithConfig(config);
  final pdf = w.pdf;
  final saved = w.withDoc(buildTestPdf(foreignAnnot: true), (doc) {
    final page = pdf.FPDF_LoadPage(doc, 0);
    final text = pdf.FPDFText_LoadPage(page);
    for (final (subtype, needle, id, color) in [
      (FPDF_ANNOT_HIGHLIGHT, 'quick brown fox', 'noap-highlight', (255, 235, 59)),
      (FPDF_ANNOT_UNDERLINE, 'highlight, underline', 'noap-underline', (21, 101, 192)),
      (FPDF_ANNOT_SQUIGGLY, 'round trip', 'noap-squiggly', (198, 40, 40)),
    ]) {
      pdf.FPDFPage_CloseAnnot(
        w.addMarkup(page, subtype, w.findQuads(text, needle), id, needle, color),
      );
    }
    pdf.FPDFText_ClosePage(text);
    pdf.FPDF_ClosePage(page); // no rendering: nothing generates an AP
    return w.save(doc, incremental: false);
  });
  File(args.first).writeAsBytesSync(saved);
  w.withDoc(saved, (doc) {
    final page = pdf.FPDF_LoadPage(doc, 0);
    for (var i = 0; i < pdf.FPDFPage_GetAnnotCount(page); i++) {
      final a = pdf.FPDFPage_GetAnnot(page, i);
      print('${w.getString(a, 'NM')}: AP=${w.getAp(a).isEmpty ? 'none' : 'present'}');
      pdf.FPDFPage_CloseAnnot(a);
    }
    pdf.FPDF_ClosePage(page);
  });
}
