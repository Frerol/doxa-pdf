// SPDX-License-Identifier: GPL-3.0-or-later
//
// Spike C (issue #7): write study annotations with PDFium, save
// incrementally, reopen and render. Throwaway prototype.
//
//   dart run bin/annot_write.dart <out-dir>
//
// For each test page variant it writes <variant>-original.pdf,
// <variant>-annotated.pdf and <variant>-pdfium.png, and prints a report.

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:annot_write/test_pdfs.dart';
import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:pdfium_ffi/pdfium_ffi.dart';

late final PdfiumBindings pdf;

void main(List<String> args) {
  final out = Directory(args.isEmpty ? 'out' : args.first)
    ..createSync(recursive: true);
  pdf = openPdfium();
  final config = calloc<FPDF_LIBRARY_CONFIG_>()..ref.version = 2;
  pdf.FPDF_InitLibraryWithConfig(config);
  calloc.free(config);

  final variants = <String, Uint8List>{
    'plain': buildTestPdf(),
    'rotate90': buildTestPdf(rotate: 90),
    'rotate270': buildTestPdf(rotate: 270),
    'cropbox': buildTestPdf(cropBox: [40, 380, 560, 760]),
    'foreign': buildTestPdf(foreignAnnot: true),
  };
  for (final MapEntry(key: name, value: bytes) in variants.entries) {
    File('${out.path}/$name-original.pdf').writeAsBytesSync(bytes);
    final annotated = annotate(bytes);
    File('${out.path}/$name-annotated.pdf').writeAsBytesSync(annotated);
    stdout.writeln('== $name');
    verify(bytes, annotated, '${out.path}/$name-pdfium.png');
  }
  pdf.FPDF_DestroyLibrary();
}

// --------------------------------------------------------------------------
// Writing

Uint8List annotate(Uint8List original) {
  return withDoc(original, (doc) {
    final page = pdf.FPDF_LoadPage(doc, 0);
    final text = pdf.FPDFText_LoadPage(page);

    // E1: highlight whose appearance is a content-stream string (SetAP).
    final quads1 = findQuads(text, 'quick brown fox');
    final h1 = addMarkup(
      page,
      FPDF_ANNOT_HIGHLIGHT,
      quads1,
      'e1-highlight-setap',
      'quick brown fox',
      (255, 235, 59),
    );
    final r = unionRect(quads1);
    setAp(
      h1,
      'q 1 0.92 0.23 rg ${r.l} ${r.b} ${r.r - r.l} ${r.t - r.b} re f Q',
    );
    pdf.FPDFPage_CloseAnnot(h1);

    // E2: highlight / underline / squiggly with no AP; PDFium is asked to
    // generate one by rendering with FPDF_ANNOT before saving.
    for (final (subtype, needle, id, color) in [
      (
        FPDF_ANNOT_HIGHLIGHT,
        'lazy dog',
        'e2-highlight-generated',
        (165, 214, 167),
      ),
      (
        FPDF_ANNOT_UNDERLINE,
        'highlight, underline',
        'e2-underline-generated',
        (21, 101, 192),
      ),
      (
        FPDF_ANNOT_SQUIGGLY,
        'round trip',
        'e2-squiggly-generated',
        (198, 40, 40),
      ),
    ]) {
      pdf.FPDFPage_CloseAnnot(
        addMarkup(page, subtype, findQuads(text, needle), id, needle, color),
      );
    }

    // E3: pressure-variable ink; AP built from a filled path page object.
    addInk(
      page,
      'e3-ink-pen',
      base: 300,
      width: 2.4,
      color: (21, 101, 192),
      multiply: false,
    );
    // E3b: highlighter ink with Multiply blend.
    addInk(
      page,
      'e3b-ink-highlighter',
      base: 560,
      width: 14,
      color: (255, 213, 79),
      multiply: true,
    );

    pdf.FPDFText_ClosePage(text);

    // Trigger PDFium's AP generation for annotations without /AP (E2).
    renderPage(page, scale: 0.5, annots: true);
    pdf.FPDF_ClosePage(page);
    return save(doc, incremental: true);
  });
}

typedef Rgb = (int, int, int);
typedef Rect = ({double l, double t, double r, double b});

List<Rect> findQuads(Pointer<fpdf_textpage_t__> text, String needle) {
  final w = needle.toNativeUtf16().cast<UnsignedShort>();
  final h = pdf.FPDFText_FindStart(text, w, 0, 0);
  final rects = <Rect>[];
  if (pdf.FPDFText_FindNext(h) != 0) {
    final start = pdf.FPDFText_GetSchResultIndex(h);
    final count = pdf.FPDFText_GetSchCount(h);
    final n = pdf.FPDFText_CountRects(text, start, count);
    final v = calloc<Double>(4);
    for (var i = 0; i < n; i++) {
      pdf.FPDFText_GetRect(text, i, v, v + 1, v + 2, v + 3);
      rects.add((l: v[0], t: v[1], r: v[2], b: v[3]));
    }
    calloc.free(v);
  }
  pdf.FPDFText_FindClose(h);
  calloc.free(w);
  if (rects.isEmpty) throw StateError('"$needle" not found');
  return rects;
}

Rect unionRect(List<Rect> rs) => (
  l: rs.map((r) => r.l).reduce(math.min),
  t: rs.map((r) => r.t).reduce(math.max),
  r: rs.map((r) => r.r).reduce(math.max),
  b: rs.map((r) => r.b).reduce(math.min),
);

Pointer<fpdf_annotation_t__> addMarkup(
  Pointer<fpdf_page_t__> page,
  int subtype,
  List<Rect> rects,
  String id,
  String contents,
  Rgb color,
) {
  final a = pdf.FPDFPage_CreateAnnot(page, subtype);
  final q = calloc<FS_QUADPOINTSF>();
  for (final r in rects) {
    // Acrobat order: upper-left, upper-right, lower-left, lower-right.
    q.ref
      ..x1 = r.l
      ..y1 = r.t
      ..x2 = r.r
      ..y2 = r.t
      ..x3 = r.l
      ..y3 = r.b
      ..x4 = r.r
      ..y4 = r.b;
    check(pdf.FPDFAnnot_AppendAttachmentPoints(a, q), 'AppendAttachmentPoints');
  }
  calloc.free(q);
  final u = unionRect(rects);
  setRect(a, (l: u.l - 1, t: u.t + 1, r: u.r + 1, b: u.b - 1));
  common(a, id, contents, color);
  return a;
}

void addInk(
  Pointer<fpdf_page_t__> page,
  String id, {
  required double base,
  required double width,
  required Rgb color,
  required bool multiply,
}) {
  // Synthetic handwriting-like stroke in PDF user space with pressure.
  final pts = <(double, double, double)>[
    for (var i = 0; i <= 120; i++)
      (
        80 + i * 3.6,
        base + 18 * math.sin(i / 9) + 6 * math.sin(i / 2.7),
        0.25 + 0.7 * math.sin(math.pi * i / 120),
      ),
  ];
  final a = pdf.FPDFPage_CreateAnnot(page, FPDF_ANNOT_INK);

  // /InkList: the centreline, for compatibility and editing.
  final ink = calloc<FS_POINTF_>(pts.length);
  for (var i = 0; i < pts.length; i++) {
    ink[i]
      ..x = pts[i].$1
      ..y = pts[i].$2;
  }
  check(pdf.FPDFAnnot_AddInkStroke(a, ink, pts.length) >= 0, 'AddInkStroke');
  calloc.free(ink);

  // Appearance: the variable-width outline as one filled path.
  final outline = outlineOf(pts, width);
  final path = pdf.FPDFPageObj_CreateNewPath(
    outline.first.$1,
    outline.first.$2,
  );
  for (final p in outline.skip(1)) {
    pdf.FPDFPath_LineTo(path, p.$1, p.$2);
  }
  pdf.FPDFPath_Close(path);
  pdf.FPDFPath_SetDrawMode(path, FPDF_FILLMODE_WINDING, 0);
  pdf.FPDFPageObj_SetFillColor(path, color.$1, color.$2, color.$3, 255);
  if (multiply) {
    final bm = 'Multiply'.toNativeUtf8().cast<Char>();
    pdf.FPDFPageObj_SetBlendMode(path, bm);
    calloc.free(bm);
  }
  final xs = outline.map((p) => p.$1), ys = outline.map((p) => p.$2);
  setRect(a, (
    l: xs.reduce(math.min) - 1,
    t: ys.reduce(math.max) + 1,
    r: xs.reduce(math.max) + 1,
    b: ys.reduce(math.min) - 1,
  ));
  // Dictionary first: SetBorder clears /AP and SetColor fails once an AP
  // exists, so the appearance object must be appended last.
  pdf.FPDFAnnot_SetBorder(a, 0, 0, width);
  common(a, id, '', color);
  // Raw pressure for lossless re-editing (private key).
  setString(
    a,
    'DoxaPressure',
    pts
        .map((p) => (p.$3 * 255).round().toRadixString(16).padLeft(2, '0'))
        .join(),
  );
  check(pdf.FPDFAnnot_AppendObject(a, path), 'AppendObject');
  pdf.FPDFPage_CloseAnnot(a);
}

List<(double, double)> outlineOf(List<(double, double, double)> pts, double w) {
  final left = <(double, double)>[], right = <(double, double)>[];
  for (var i = 0; i < pts.length; i++) {
    final a = pts[math.max(i - 1, 0)], b = pts[math.min(i + 1, pts.length - 1)];
    var nx = -(b.$2 - a.$2), ny = b.$1 - a.$1;
    final len = math.sqrt(nx * nx + ny * ny);
    nx /= len;
    ny /= len;
    final r = w / 2 * (0.35 + 1.3 * pts[i].$3);
    left.add((pts[i].$1 + nx * r, pts[i].$2 + ny * r));
    right.add((pts[i].$1 - nx * r, pts[i].$2 - ny * r));
  }
  return [...left, ...right.reversed];
}

void common(Pointer<fpdf_annotation_t__> a, String id, String contents, Rgb c) {
  check(
    pdf.FPDFAnnot_SetColor(
      a,
      FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
      c.$1,
      c.$2,
      c.$3,
      255,
    ),
    'SetColor',
  );
  pdf.FPDFAnnot_SetFlags(a, FPDF_ANNOT_FLAG_PRINT);
  setString(a, 'NM', id);
  setString(a, 'T', 'Doxa PDF spike');
  if (contents.isNotEmpty) setString(a, 'Contents', contents);
  setString(a, 'M', 'D:20261124120000Z');
}

void setRect(Pointer<fpdf_annotation_t__> a, Rect r) {
  final p = calloc<FS_RECTF_>();
  p.ref
    ..left = r.l
    ..top = r.t
    ..right = r.r
    ..bottom = r.b;
  check(pdf.FPDFAnnot_SetRect(a, p), 'SetRect');
  calloc.free(p);
}

void setString(Pointer<fpdf_annotation_t__> a, String key, String value) {
  final k = key.toNativeUtf8().cast<Char>();
  final v = value.toNativeUtf16().cast<UnsignedShort>();
  check(pdf.FPDFAnnot_SetStringValue(a, k, v), 'SetStringValue($key)');
  calloc
    ..free(k)
    ..free(v);
}

void setAp(Pointer<fpdf_annotation_t__> a, String stream) {
  final v = stream.toNativeUtf16().cast<UnsignedShort>();
  check(pdf.FPDFAnnot_SetAP(a, FPDF_ANNOT_APPEARANCEMODE_NORMAL, v), 'SetAP');
  calloc.free(v);
}

String getString(Pointer<fpdf_annotation_t__> a, String key) {
  final k = key.toNativeUtf8().cast<Char>();
  final n = pdf.FPDFAnnot_GetStringValue(a, k, nullptr, 0);
  final buf = calloc<UnsignedShort>(n ~/ 2 + 1);
  pdf.FPDFAnnot_GetStringValue(a, k, buf, n);
  final s = String.fromCharCodes(
    buf.cast<Uint16>().asTypedList(n ~/ 2 - 1 < 0 ? 0 : n ~/ 2 - 1),
  );
  calloc
    ..free(k)
    ..free(buf);
  return s;
}

String getAp(Pointer<fpdf_annotation_t__> a) {
  final n = pdf.FPDFAnnot_GetAP(
    a,
    FPDF_ANNOT_APPEARANCEMODE_NORMAL,
    nullptr,
    0,
  );
  if (n <= 2) return '';
  final buf = calloc<UnsignedShort>(n ~/ 2);
  pdf.FPDFAnnot_GetAP(a, FPDF_ANNOT_APPEARANCEMODE_NORMAL, buf, n);
  final s = String.fromCharCodes(buf.cast<Uint16>().asTypedList(n ~/ 2 - 1));
  calloc.free(buf);
  return s;
}

/// Accepts `bool` or PDFium's `FPDF_BOOL` (int, 0 = failure).
void check(Object ok, String what) {
  if (ok == false || ok == 0) throw StateError('$what failed');
}

// --------------------------------------------------------------------------
// Saving (FPDF_FILEWRITE callback into a Dart buffer)

final _sink = BytesBuilder(copy: true);

int _writeBlock(Pointer<FPDF_FILEWRITE_> self, Pointer<Void> data, int size) {
  _sink.add(data.cast<Uint8>().asTypedList(size));
  return 1;
}

Uint8List save(Pointer<fpdf_document_t__> doc, {required bool incremental}) {
  final cb =
      NativeCallable<
        Int Function(Pointer<FPDF_FILEWRITE_>, Pointer<Void>, UnsignedLong)
      >.isolateLocal(_writeBlock, exceptionalReturn: 0);
  final fw = calloc<FPDF_FILEWRITE_>()
    ..ref.version = 1
    ..ref.WriteBlock = cb.nativeFunction;
  _sink.clear();
  check(
    pdf.FPDF_SaveAsCopy(doc, fw, incremental ? FPDF_INCREMENTAL : 0) != 0,
    'SaveAsCopy',
  );
  calloc.free(fw);
  cb.close();
  return _sink.takeBytes();
}

// --------------------------------------------------------------------------
// Reading back

T withDoc<T>(Uint8List bytes, T Function(Pointer<fpdf_document_t__>) body) {
  final buf = malloc<Uint8>(bytes.length);
  buf.asTypedList(bytes.length).setAll(0, bytes);
  final doc = pdf.FPDF_LoadMemDocument64(buf.cast(), bytes.length, nullptr);
  check(doc != nullptr, 'load (error ${pdf.FPDF_GetLastError()})');
  try {
    return body(doc);
  } finally {
    pdf.FPDF_CloseDocument(doc);
    malloc.free(buf);
  }
}

img.Image renderPage(
  Pointer<fpdf_page_t__> page, {
  required double scale,
  required bool annots,
}) {
  // FPDF_GetPageWidthF already accounts for /Rotate and the CropBox.
  final w = (pdf.FPDF_GetPageWidthF(page) * scale).round();
  final h = (pdf.FPDF_GetPageHeightF(page) * scale).round();
  final bmp = pdf.FPDFBitmap_Create(w, h, 1);
  pdf.FPDFBitmap_FillRect(bmp, 0, 0, w, h, 0xFFFFFFFF);
  pdf.FPDF_RenderPageBitmap(bmp, page, 0, 0, w, h, 0, annots ? FPDF_ANNOT : 0);
  final stride = pdf.FPDFBitmap_GetStride(bmp);
  final src = pdf.FPDFBitmap_GetBuffer(bmp)
      .cast<Uint8>()
      .asTypedList(stride * h);
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * stride + x * 4;
      image.setPixelRgb(x, y, src[i + 2], src[i + 1], src[i]);
    }
  }
  pdf.FPDFBitmap_Destroy(bmp);
  return image;
}

void verify(Uint8List original, Uint8List saved, String pngPath) {
  final prefix =
      saved.length > original.length &&
      List.generate(
        original.length,
        (i) => saved[i] == original[i],
      ).every((b) => b);
  stdout.writeln(
    '  incremental: $prefix (${original.length} -> ${saved.length} bytes)',
  );
  withDoc(saved, (doc) {
    final page = pdf.FPDF_LoadPage(doc, 0);
    final n = pdf.FPDFPage_GetAnnotCount(page);
    for (var i = 0; i < n; i++) {
      final a = pdf.FPDFPage_GetAnnot(page, i);
      final nm = getString(a, 'NM');
      final ap = getAp(a);
      final extra = switch (nm) {
        'foreign-1' => 'Foo=${getString(a, 'Foo')} T=${getString(a, 'T')}',
        _ when nm.startsWith('e3') =>
          'inkList=${pdf.FPDFAnnot_GetInkListCount(a)} '
              'pressure=${getString(a, 'DoxaPressure').length ~/ 2} samples',
        _ => 'contents="${getString(a, 'Contents')}"',
      };
      stdout.writeln(
        '  [$i] subtype=${pdf.FPDFAnnot_GetSubtype(a)} NM=$nm '
        'AP=${ap.isEmpty ? 'none' : '${ap.length} chars: ${ap.replaceAll('\n', ' ').substring(0, math.min(70, ap.length))}'} '
        '$extra',
      );
      pdf.FPDFPage_CloseAnnot(a);
    }
    File(pngPath).writeAsBytesSync(
      img.encodePng(renderPage(page, scale: 1.5, annots: true)),
    );
    pdf.FPDF_ClosePage(page);
  });
}
