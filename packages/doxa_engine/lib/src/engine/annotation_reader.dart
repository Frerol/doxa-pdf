// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ffi';
import 'dart:math' as math;

import 'package:doxa_core/doxa_core.dart';
import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

import '../api/types.dart';

/// Reads a page's annotations into the `doxa_core` model (FR-ANNO-002).
///
/// It only reads: no key is set and no appearance is generated, so the
/// editing instance it reads from keeps every annotation as the file has
/// it. Must only be used from the engine isolate.
final class AnnotationReader {
  AnnotationReader(this._pdf);

  final PdfiumBindings _pdf;

  /// Guards against hostile pages.
  static const maxAnnotationsPerPage = 10000;
  static const maxQuadsPerMarkup = 10000;
  static const maxPathsPerInk = 10000;
  static const maxPointsPerPath = 100000;

  /// How deep and how far [_appearanceColor] looks into an appearance.
  static const _maxFormDepth = 4;
  static const _maxObjectsVisited = 256;

  /// Subtypes left out: popups belong to their markup, links are read by
  /// `pageLinks`, and form fields are not study annotations.
  static const _skipped = {
    FPDF_ANNOT_POPUP,
    FPDF_ANNOT_LINK,
    FPDF_ANNOT_WIDGET,
    FPDF_ANNOT_XFAWIDGET,
  };

  /// `/Subtype` names by PDFium's subtype numbers (`fpdf_annot.h`).
  static const _subtypeNames = [
    'Unknown', 'Text', 'Link', 'FreeText', 'Line', 'Square', 'Circle', //
    'Polygon', 'PolyLine', 'Highlight', 'Underline', 'Squiggly',
    'StrikeOut', 'Stamp', 'Caret', 'Ink', 'Popup', 'FileAttachment',
    'Sound', 'Movie', 'Widget', 'Screen', 'PrinterMark', 'TrapNet',
    'Watermark', '3D', 'RichMedia', 'XFAWidget', 'Redact',
  ];

  /// The annotations of page [pageIndex] of [doc], in `/Annots` order.
  List<Annotation> read(Pointer<fpdf_document_t__> doc, int pageIndex) {
    final page = _pdf.FPDF_LoadPage(doc, pageIndex);
    if (page == nullptr) {
      throw PdfEngineException(
        EngineErrorKind.documentError,
        'Cannot load page $pageIndex for its annotations',
      );
    }
    try {
      final count = math.min(
        _pdf.FPDFPage_GetAnnotCount(page),
        maxAnnotationsPerPage,
      );
      final annotations = <Annotation>[];
      for (var i = 0; i < count; i++) {
        final annot = _pdf.FPDFPage_GetAnnot(page, i);
        if (annot == nullptr) continue;
        try {
          final annotation = readOne(annot, pageIndex, i);
          if (annotation != null) annotations.add(annotation);
        } finally {
          _pdf.FPDFPage_CloseAnnot(annot);
        }
      }
      return annotations;
    } finally {
      _pdf.FPDF_ClosePage(page);
    }
  }

  /// Whether `read` leaves out annotations of this PDFium subtype.
  static bool isSkipped(int subtype) => _skipped.contains(subtype);

  /// The id `read` gives the annotation at [index] of page [pageIndex]:
  /// its `/NM`, or, without one, an id from its place, in memory only. It
  /// is written to the file when that annotation is edited (03 §5).
  String idOf(Pointer<fpdf_annotation_t__> annot, int pageIndex, int index) {
    final nm = _string(annot, 'NM');
    return nm == null || nm.isEmpty ? 'page$pageIndex-annot$index' : nm;
  }

  /// Whether the annotation is one of Doxa's own ([DoxaMarker]).
  bool isDoxa(Pointer<fpdf_annotation_t__> annot) => DoxaMarker.owns(
    nm: _string(annot, 'NM'),
    versionValue: _string(annot, DoxaMarker.versionKey),
  );

  /// Whether the annotation has an appearance dictionary.
  bool hasAppearance(Pointer<fpdf_annotation_t__> annot) => _has(annot, 'AP');

  /// The annotation at [index] of page [pageIndex], or null where `read`
  /// leaves it out.
  Annotation? readOne(
    Pointer<fpdf_annotation_t__> annot,
    int pageIndex,
    int index,
  ) {
    final subtype = _pdf.FPDFAnnot_GetSubtype(annot);
    if (_skipped.contains(subtype)) return null;
    final nm = _string(annot, 'NM');
    final byDoxa = DoxaMarker.owns(
      nm: nm,
      versionValue: _string(annot, DoxaMarker.versionKey),
    );
    final id = idOf(annot, pageIndex, index);
    final rect = _rect(annot);
    final color = _color(annot);
    final opacity = (_number(annot, 'CA') ?? 1).clamp(0.0, 1.0);
    final author = _string(annot, 'T');
    final contents = _string(annot, 'Contents');
    final modifiedText = _string(annot, 'M');
    final modified = modifiedText == null ? null : parsePdfDate(modifiedText);
    final flags = _pdf.FPDFAnnot_GetFlags(annot);

    OtherAnnotation other() => OtherAnnotation(
      id: id,
      pageIndex: pageIndex,
      rect: rect,
      subtype: subtype >= 0 && subtype < _subtypeNames.length
          ? _subtypeNames[subtype]
          : 'Unknown',
      color: color,
      opacity: opacity,
      author: author,
      contents: contents,
      modified: modified,
      flags: flags,
      byDoxa: byDoxa,
    );

    final kind = subtype >= 0 && subtype < _subtypeNames.length
        ? MarkupKind.fromSubtype(_subtypeNames[subtype])
        : null;
    if (kind != null) {
      final quads = _quads(annot);
      // Markup without valid quads cannot be drawn by Doxa: keep it as
      // what it is, for the review panel.
      if (quads.isEmpty) return other();
      return TextMarkup(
        id: id,
        pageIndex: pageIndex,
        kind: kind,
        quads: quads,
        rect: rect,
        text: byDoxa ? _string(annot, DoxaMarker.textKey) : null,
        color: color,
        opacity: opacity,
        author: author,
        contents: contents,
        modified: modified,
        flags: flags,
        byDoxa: byDoxa,
      );
    }
    if (subtype == FPDF_ANNOT_INK) {
      final paths = _inkPaths(annot);
      if (paths.isEmpty) return other();
      final pressures = byDoxa ? _pressures(annot) : null;
      final strokes = [
        for (final (i, points) in paths.indexed)
          InkStroke(
            points,
            pressures:
                pressures != null &&
                    pressures.length == paths.length &&
                    pressures[i].length == points.length
                ? pressures[i]
                : null,
          ),
      ];
      return InkAnnotation(
        id: id,
        pageIndex: pageIndex,
        strokes: strokes,
        width: _borderWidth(annot) ?? 1,
        tool:
            byDoxa &&
                _string(annot, DoxaMarker.toolKey) == InkTool.highlighter.name
            ? InkTool.highlighter
            : InkTool.pen,
        rect: rect,
        color: color,
        opacity: opacity,
        author: author,
        contents: contents,
        modified: modified,
        flags: flags,
        byDoxa: byDoxa,
      );
    }
    return other();
  }

  PdfRect _rect(Pointer<fpdf_annotation_t__> annot) {
    final rect = calloc<FS_RECTF_>();
    try {
      if (_pdf.FPDFAnnot_GetRect(annot, rect) == 0) {
        return const PdfRect(0, 0, 0, 0);
      }
      return PdfRect(
        rect.ref.left,
        rect.ref.bottom,
        rect.ref.right,
        rect.ref.top,
      ).normalized();
    } finally {
      calloc.free(rect);
    }
  }

  /// `/C` where PDFium can read it. PDFium refuses once an annotation has
  /// an appearance stream, as most annotations from other apps do; the
  /// colour of the first painted path of the appearance stands in for it.
  int? _color(Pointer<fpdf_annotation_t__> annot) {
    final r = calloc<UnsignedInt>(), g = calloc<UnsignedInt>();
    final b = calloc<UnsignedInt>(), a = calloc<UnsignedInt>();
    try {
      if (_pdf.FPDFAnnot_GetColor(
            annot,
            FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
            r,
            g,
            b,
            a,
          ) !=
          0) {
        // Without /C, PDFium reports a default colour; an annotation with
        // no /C has none.
        if (!_has(annot, 'C')) return null;
        return _rgb(r.value, g.value, b.value);
      }
      final budget = [_maxObjectsVisited];
      final count = _pdf.FPDFAnnot_GetObjectCount(annot);
      for (var i = 0; i < count; i++) {
        final found = _appearanceColor(
          _pdf.FPDFAnnot_GetObject(annot, i),
          0,
          budget,
          r,
          g,
          b,
          a,
        );
        if (found != null) return found;
      }
      return null;
    } finally {
      calloc
        ..free(r)
        ..free(g)
        ..free(b)
        ..free(a);
    }
  }

  int? _appearanceColor(
    Pointer<fpdf_pageobject_t__> object,
    int depth,
    List<int> budget,
    Pointer<UnsignedInt> r,
    Pointer<UnsignedInt> g,
    Pointer<UnsignedInt> b,
    Pointer<UnsignedInt> a,
  ) {
    if (object == nullptr || budget[0]-- <= 0) return null;
    switch (_pdf.FPDFPageObj_GetType(object)) {
      case FPDF_PAGEOBJ_PATH:
        final fill = calloc<Int>(), stroke = calloc<Int>();
        try {
          if (_pdf.FPDFPath_GetDrawMode(object, fill, stroke) == 0) {
            return null;
          }
          final read = fill.value != FPDF_FILLMODE_NONE
              ? _pdf.FPDFPageObj_GetFillColor(object, r, g, b, a)
              : stroke.value != 0
              ? _pdf.FPDFPageObj_GetStrokeColor(object, r, g, b, a)
              : 0;
          return read == 0 ? null : _rgb(r.value, g.value, b.value);
        } finally {
          calloc
            ..free(fill)
            ..free(stroke);
        }
      case FPDF_PAGEOBJ_FORM when depth < _maxFormDepth:
        final count = _pdf.FPDFFormObj_CountObjects(object);
        for (var i = 0; i < count; i++) {
          final found = _appearanceColor(
            _pdf.FPDFFormObj_GetObject(object, i),
            depth + 1,
            budget,
            r,
            g,
            b,
            a,
          );
          if (found != null) return found;
        }
        return null;
      default:
        return null;
    }
  }

  static int _rgb(int r, int g, int b) =>
      (r & 0xFF) << 16 | (g & 0xFF) << 8 | b & 0xFF;

  List<PdfQuad> _quads(Pointer<fpdf_annotation_t__> annot) {
    final count = math.min(
      _pdf.FPDFAnnot_CountAttachmentPoints(annot),
      maxQuadsPerMarkup,
    );
    final quad = calloc<FS_QUADPOINTSF>();
    try {
      return [
        for (var i = 0; i < count; i++)
          if (_pdf.FPDFAnnot_GetAttachmentPoints(annot, i, quad) != 0)
            PdfQuad(
              PdfPoint(quad.ref.x1, quad.ref.y1),
              PdfPoint(quad.ref.x2, quad.ref.y2),
              PdfPoint(quad.ref.x3, quad.ref.y3),
              PdfPoint(quad.ref.x4, quad.ref.y4),
            ),
      ];
    } finally {
      calloc.free(quad);
    }
  }

  List<List<PdfPoint>> _inkPaths(Pointer<fpdf_annotation_t__> annot) {
    final count = math.min(
      _pdf.FPDFAnnot_GetInkListCount(annot),
      maxPathsPerInk,
    );
    final paths = <List<PdfPoint>>[];
    for (var i = 0; i < count; i++) {
      final length = math.min(
        _pdf.FPDFAnnot_GetInkListPath(annot, i, nullptr, 0),
        maxPointsPerPath,
      );
      if (length <= 0) continue;
      final buffer = calloc<FS_POINTF_>(length);
      try {
        final read = _pdf.FPDFAnnot_GetInkListPath(annot, i, buffer, length);
        if (read != length) continue;
        paths.add([
          for (var j = 0; j < length; j++) PdfPoint(buffer[j].x, buffer[j].y),
        ]);
      } finally {
        calloc.free(buffer);
      }
    }
    return paths;
  }

  List<List<double>>? _pressures(Pointer<fpdf_annotation_t__> annot) {
    final text = _string(annot, DoxaMarker.pressureKey);
    return text == null ? null : PressureCodec.decode(text);
  }

  double? _borderWidth(Pointer<fpdf_annotation_t__> annot) {
    final h = calloc<Float>(), v = calloc<Float>(), w = calloc<Float>();
    try {
      if (_pdf.FPDFAnnot_GetBorder(annot, h, v, w) == 0) return null;
      return w.value > 0 ? w.value : null;
    } finally {
      calloc
        ..free(h)
        ..free(v)
        ..free(w);
    }
  }

  double? _number(Pointer<fpdf_annotation_t__> annot, String key) {
    final value = calloc<Float>();
    final name = _key(key);
    try {
      return _pdf.FPDFAnnot_GetNumberValue(annot, name, value) == 0
          ? null
          : value.value;
    } finally {
      calloc
        ..free(value)
        ..free(name);
    }
  }

  bool _has(Pointer<fpdf_annotation_t__> annot, String key) {
    final name = _key(key);
    try {
      return _pdf.FPDFAnnot_HasKey(annot, name) != 0;
    } finally {
      calloc.free(name);
    }
  }

  /// A text string value, or null when [key] is absent.
  String? _string(Pointer<fpdf_annotation_t__> annot, String key) {
    final name = _key(key);
    try {
      if (_pdf.FPDFAnnot_HasKey(annot, name) == 0) return null;
      final bytes = _pdf.FPDFAnnot_GetStringValue(annot, name, nullptr, 0);
      if (bytes <= 2) return '';
      final buffer = calloc<UnsignedShort>(bytes ~/ 2);
      try {
        final written = _pdf.FPDFAnnot_GetStringValue(
          annot,
          name,
          buffer,
          bytes,
        );
        final units = math.min(written, bytes) ~/ 2 - 1;
        if (units <= 0) return '';
        return String.fromCharCodes(buffer.cast<Uint16>().asTypedList(units));
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(name);
    }
  }

  Pointer<Char> _key(String key) => key.toNativeUtf8().cast<Char>();
}
