// SPDX-License-Identifier: GPL-3.0-or-later
//
// Spike A (issue #5): how expensive is each rendering operation in PDFium?
//   dart run bin/render_probe.dart <file.pdf> [viewWidthPx]
// Throwaway prototype.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

late final PdfiumBindings pdf;

void main(List<String> args) {
  final path = args.first;
  final viewWidth = args.length > 1 ? int.parse(args[1]) : 1440; // tablet px
  pdf = openPdfium();
  final config = calloc<FPDF_LIBRARY_CONFIG_>()..ref.version = 2;
  pdf.FPDF_InitLibraryWithConfig(config);

  final sw = Stopwatch()..start();
  final p = path.toNativeUtf8().cast<Char>();
  final doc = pdf.FPDF_LoadDocument(p, nullptr);
  if (doc == nullptr) throw StateError('load failed ${pdf.FPDF_GetLastError()}');
  final openMs = sw.elapsedMicroseconds / 1000;
  final n = pdf.FPDF_GetPageCount(doc);

  // Layout needs every page size, ideally without loading pages.
  sw.reset();
  final size = calloc<FS_SIZEF_>();
  var totalHeight = 0.0;
  for (var i = 0; i < n; i++) {
    pdf.FPDF_GetPageSizeByIndexF(doc, i, size);
    totalHeight += size.ref.height;
  }
  final sizesMs = sw.elapsedMicroseconds / 1000;
  print('${path.split('/').last}: pages=$n open=${openMs.toStringAsFixed(1)}ms '
      'allPageSizes=${sizesMs.toStringAsFixed(1)}ms (${(sizesMs * 1000 / n).toStringAsFixed(1)}µs/page) '
      'docHeight=${totalHeight.round()}pt');

  final samples = [for (var i = 0; i < n; i += (n ~/ 20).clamp(1, n)) i];
  final load = <double>[], thumb = <double>[], fit = <double>[], tile = <double>[], text = <double>[];
  for (final i in samples) {
    sw.reset();
    final page = pdf.FPDF_LoadPage(doc, i);
    load.add(sw.elapsedMicroseconds / 1000);
    final w = pdf.FPDF_GetPageWidthF(page), h = pdf.FPDF_GetPageHeightF(page);

    // Thumbnail: 160 px wide.
    thumb.add(_render(page, 160 / w, 160, (160 * h / w).round(), 0, 0));
    // Fit width on the tablet: one full-page bitmap.
    final s = viewWidth / w;
    fit.add(_render(page, s, viewWidth, (h * s).round(), 0, 0));
    // 512 px tile at 2x zoom, from the middle of the page.
    final z = s * 2;
    tile.add(_render(page, z, 512, 512, (w * z / 2).round(), (h * z / 2).round()));

    sw.reset();
    final tp = pdf.FPDFText_LoadPage(page);
    pdf.FPDFText_CountChars(tp);
    pdf.FPDFText_ClosePage(tp);
    text.add(sw.elapsedMicroseconds / 1000);
    pdf.FPDF_ClosePage(page);
  }
  String st(List<double> v) {
    v.sort();
    return 'p50=${v[v.length ~/ 2].toStringAsFixed(1)} max=${v.last.toStringAsFixed(1)}';
  }
  print('  loadPage ${st(load)} | thumb160 ${st(thumb)} | fitWidth${viewWidth}px ${st(fit)} '
      '| tile512@2x ${st(tile)} | textPage ${st(text)}  (ms, ${samples.length} pages)');
  print('  RSS=${(_rssKb() / 1024).round()}MB');
  pdf.FPDF_CloseDocument(doc);
  pdf.FPDF_DestroyLibrary();
}

/// Renders the region at (ox, oy) of the page scaled by [scale] into a
/// w x h RGBA bitmap backed by Dart-owned native memory. Returns ms.
double _render(Pointer<fpdf_page_t__> page, double scale, int w, int h, int ox, int oy) {
  final sw = Stopwatch()..start();
  final buf = malloc<Uint8>(w * h * 4);
  final bmp = pdf.FPDFBitmap_CreateEx(w, h, FPDFBitmap_BGRA, buf.cast(), w * 4);
  pdf.FPDFBitmap_FillRect(bmp, 0, 0, w, h, 0xFFFFFFFF);
  final m = calloc<FS_MATRIX_>();
  m.ref
    ..a = scale
    ..d = scale
    ..e = -ox.toDouble()
    ..f = -oy.toDouble();
  final clip = calloc<FS_RECTF_>();
  clip.ref
    ..left = 0
    ..top = 0
    ..right = w.toDouble()
    ..bottom = h.toDouble();
  pdf.FPDF_RenderPageBitmapWithMatrix(bmp, page, m, clip, FPDF_REVERSE_BYTE_ORDER);
  pdf.FPDFBitmap_Destroy(bmp);
  calloc
    ..free(m)
    ..free(clip);
  malloc.free(buf);
  return sw.elapsedMicroseconds / 1000;
}

int _rssKb() {
  final line = File('/proc/self/status').readAsLinesSync().firstWhere((l) => l.startsWith('VmRSS'));
  return int.parse(line.split(RegExp(r'\s+'))[1]);
}
