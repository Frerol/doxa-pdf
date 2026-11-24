// SPDX-License-Identifier: GPL-3.0-or-later
// Full vs incremental save time on a large file (Spike C probe).
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
  final bytes = File(args.first).readAsBytesSync();
  for (final incremental in [false, true]) {
    for (final visited in [1, 30]) {
      final sw = Stopwatch()..start();
      late int out;
      w.withDoc(bytes, (doc) {
        final load = sw.elapsedMilliseconds;
        // Visit (render) pages, like a reading session would.
        for (var p = 0; p < visited; p++) {
          final page = pdf.FPDF_LoadPage(doc, p);
          w.renderPage(page, scale: 0.3, annots: false);
          pdf.FPDF_ClosePage(page);
        }
        final page = pdf.FPDF_LoadPage(doc, 0);
        final a = pdf.FPDFPage_CreateAnnot(page, FPDF_ANNOT_INK);
        w.setRect(a, (l: 90, t: 320, r: 310, b: 280));
        final path = pdf.FPDFPageObj_CreateNewPath(100, 300);
        pdf.FPDFPath_LineTo(path, 300, 310);
        pdf.FPDFPath_Close(path);
        pdf.FPDFPath_SetDrawMode(path, FPDF_FILLMODE_WINDING, 0);
        pdf.FPDFAnnot_AppendObject(a, path);
        pdf.FPDFPage_CloseAnnot(a);
        pdf.FPDF_ClosePage(page);
        final t0 = sw.elapsedMilliseconds;
        out = w.save(doc, incremental: incremental).length;
        print('${incremental ? 'incremental' : 'full       '} visited=$visited '
            'load=${load}ms save=${sw.elapsedMilliseconds - t0}ms '
            'output=${(out / 1048576).toStringAsFixed(1)}MB '
            '(+${((out - bytes.length) / 1048576).toStringAsFixed(1)}MB)');
      });
    }
  }
}
