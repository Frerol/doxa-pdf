// SPDX-License-Identifier: GPL-3.0-or-later
// Which objects does PDFium write in an incremental save? (Spike C probe)
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

import 'annot_write.dart' as w;

void main(List<String> files) {
  w.pdf = openPdfium();
  final config = calloc<FPDF_LIBRARY_CONFIG_>()..ref.version = 2;
  w.pdf.FPDF_InitLibraryWithConfig(config);
  final pdf = w.pdf;
  for (final f in files) {
    final original = File(f).readAsBytesSync();
    final saved = w.withDoc(original, (doc) {
      final page = pdf.FPDF_LoadPage(doc, 0);
      final a = pdf.FPDFPage_CreateAnnot(page, FPDF_ANNOT_INK);
      w.setRect(a, (l: 90, t: 320, r: 310, b: 280));
      w.setString(a, 'NM', 'probe');
      final path = pdf.FPDFPageObj_CreateNewPath(100, 300);
      pdf.FPDFPath_LineTo(path, 300, 310);
      pdf.FPDFPath_LineTo(path, 300, 290);
      pdf.FPDFPath_Close(path);
      pdf.FPDFPath_SetDrawMode(path, FPDF_FILLMODE_WINDING, 0);
      pdf.FPDFAnnot_AppendObject(a, path);
      pdf.FPDFPage_CloseAnnot(a);
      pdf.FPDF_ClosePage(page);
      return w.save(doc, incremental: Platform.environment['FULL'] == null);
    });
    final update = String.fromCharCodes(saved.sublist(original.length));
    final objs = RegExp(r'(\d+) 0 obj').allMatches(update).map((m) => m[1]).toList();
    print('${f.split('/').last}: +${saved.length - original.length} bytes, objects written: $objs');
    File(f.replaceFirst('.pdf', Platform.environment['FULL'] == null ? '-incr.pdf' : '-full.pdf')).writeAsBytesSync(saved);
  }
}
