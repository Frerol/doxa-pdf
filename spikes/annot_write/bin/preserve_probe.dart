// SPDX-License-Identifier: GPL-3.0-or-later
// Open a file annotated by another app, add one ink stroke, full-save.
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

import 'annot_write.dart' as w;

void main(List<String> args) {
  w.pdf = openPdfium();
  final config = calloc<FPDF_LIBRARY_CONFIG_>()..ref.version = 2;
  w.pdf.FPDF_InitLibraryWithConfig(config);
  final pdf = w.pdf;
  final saved = w.withDoc(File(args[0]).readAsBytesSync(), (doc) {
    final page = pdf.FPDF_LoadPage(doc, 0);
    for (var i = 0; i < pdf.FPDFPage_GetAnnotCount(page); i++) {
      final a = pdf.FPDFPage_GetAnnot(page, i);
      print('read: subtype=${pdf.FPDFAnnot_GetSubtype(a)} NM=${w.getString(a, 'NM')}');
      pdf.FPDFPage_CloseAnnot(a);
    }
    final a = pdf.FPDFPage_CreateAnnot(page, FPDF_ANNOT_INK);
    w.setRect(a, (l: 90, t: 420, r: 310, b: 380));
    w.setString(a, 'NM', 'doxa-after-other-app');
    final path = pdf.FPDFPageObj_CreateNewPath(100, 400);
    pdf.FPDFPath_LineTo(path, 300, 410);
    pdf.FPDFPath_LineTo(path, 300, 395);
    pdf.FPDFPath_Close(path);
    pdf.FPDFPath_SetDrawMode(path, FPDF_FILLMODE_WINDING, 0);
    pdf.FPDFAnnot_AppendObject(a, path);
    pdf.FPDFPage_CloseAnnot(a);
    pdf.FPDF_ClosePage(page);
    return w.save(doc, incremental: false);
  });
  File(args[1]).writeAsBytesSync(saved);
}
