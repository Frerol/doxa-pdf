// SPDX-License-Identifier: GPL-3.0-or-later
// Which call replaces the object-based ink appearance? (Spike C probe)
import 'dart:ffi';
import 'dart:math' as math;

import 'package:annot_write/test_pdfs.dart';
import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

import 'annot_write.dart' as w;

void main() {
  w.pdf = openPdfium();
  final config = calloc<FPDF_LIBRARY_CONFIG_>()..ref.version = 2;
  w.pdf.FPDF_InitLibraryWithConfig(config);
  final pdf = w.pdf;
  for (final order in ['object-last', 'object-first', 'no-inklist']) {
    w.withDoc(buildTestPdf(), (doc) {
      final page = pdf.FPDF_LoadPage(doc, 0);
      final a = pdf.FPDFPage_CreateAnnot(page, FPDF_ANNOT_INK);
      String ap(String step) =>
          '$step: ${w.getAp(a).split(' ').take(4).join(' ')}';
      final log = <String>[];
      void object() {
        final path = pdf.FPDFPageObj_CreateNewPath(100, 300);
        for (var i = 1; i < 50; i++) {
          pdf.FPDFPath_LineTo(path, 100 + i * 4.0, 300 + 10 * math.sin(i / 5));
        }
        pdf.FPDFPath_LineTo(path, 300, 290);
        pdf.FPDFPath_Close(path);
        pdf.FPDFPath_SetDrawMode(path, FPDF_FILLMODE_WINDING, 0);
        pdf.FPDFPageObj_SetFillColor(path, 200, 0, 0, 255);
        log.add('AppendObject=${pdf.FPDFAnnot_AppendObject(a, path)}');
        log.add(ap('after AppendObject'));
      }
      void inkList() {
        final pts = calloc<FS_POINTF_>(2);
        pts[0]..x = 100..y = 300;
        pts[1]..x = 300..y = 300;
        log.add('AddInkStroke=${pdf.FPDFAnnot_AddInkStroke(a, pts, 2)}');
        calloc.free(pts);
        log.add(ap('after AddInkStroke'));
      }
      w.setRect(a, (l: 90, t: 320, r: 310, b: 280));
      if (order == 'object-first') object();
      if (order != 'no-inklist') inkList();
      log.add('SetColor=${pdf.FPDFAnnot_SetColor(a, FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color, 0, 0, 200, 255)}');
      log.add(ap('after SetColor'));
      log.add('SetBorder=${pdf.FPDFAnnot_SetBorder(a, 0, 0, 3)}');
      log.add(ap('after SetBorder'));
      w.setString(a, 'NM', 'probe');
      log.add(ap('after SetStringValue'));
      if (order != 'object-first') object();
      pdf.FPDFPage_CloseAnnot(a);
      w.renderPage(page, scale: 0.5, annots: true);
      final b = pdf.FPDFPage_GetAnnot(page, 0);
      log.add('after render: ${w.getAp(b).split(' ').take(4).join(' ')}');
      pdf.FPDFPage_CloseAnnot(b);
      pdf.FPDF_ClosePage(page);
      final saved = w.save(doc, incremental: true);
      w.withDoc(saved, (d2) {
        final p2 = pdf.FPDF_LoadPage(d2, 0);
        final c = pdf.FPDFPage_GetAnnot(p2, 0);
        log.add('after save+reload: ${w.getAp(c).split(' ').take(4).join(' ')}');
        pdf.FPDFPage_CloseAnnot(c);
        pdf.FPDF_ClosePage(p2);
      });
      print('== $order\n  ${log.join('\n  ')}');
    });
  }
}
