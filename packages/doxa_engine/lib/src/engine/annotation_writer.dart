// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ffi';

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_ink/doxa_ink.dart';
import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

import '../api/types.dart';
import 'annotation_reader.dart';

typedef _Annot = Pointer<fpdf_annotation_t__>;
typedef _Page = Pointer<fpdf_page_t__>;

/// Adds, changes and deletes annotations in an editing instance, as
/// ADR-0008 decides. Must only be used from the engine isolate, and never
/// on an instance that is rendered with `FPDF_ANNOT`.
///
/// - Text markup is written without `/AP`; every tested reader draws it.
/// - Ink gets an appearance built from page objects, appended after every
///   other setter: `FPDFAnnot_SetBorder` deletes an existing appearance,
///   and `FPDFAnnot_SetColor` fails once one exists.
/// - Doxa's own annotations are rebuilt on every change. Another app's
///   annotation is patched key by key and never rebuilt, so its unknown
///   keys stay (FR-ANNO-002); a change that would need a rebuild is
///   refused with [EngineErrorKind.unsupportedEdit].
final class AnnotationWriter {
  AnnotationWriter(this._pdf, this._reader);

  final PdfiumBindings _pdf;
  final AnnotationReader _reader;

  /// The clock for `/M` and `/CreationDate` when an annotation has none.
  DateTime Function() now = DateTime.now;

  /// Adds Doxa's [annotations] to their pages.
  void add(Pointer<fpdf_document_t__> doc, List<Annotation> annotations) {
    for (final annotation in annotations) {
      if (!DoxaMarker.isDoxaId(annotation.id)) {
        throw PdfEngineException(
          EngineErrorKind.unsupportedEdit,
          'Doxa only creates annotations with its own ids: ${annotation.id}',
        );
      }
      _onPage(doc, annotation.pageIndex, (page) {
        if (_find(page, annotation.pageIndex, annotation.id) != null) {
          throw PdfEngineException(
            EngineErrorKind.unsupportedEdit,
            'Already on page ${annotation.pageIndex}: ${annotation.id}',
          );
        }
        _create(page, annotation);
      });
    }
  }

  /// Changes the annotation with [annotation]'s id to match it, and
  /// returns it as the page now holds it. A foreign annotation without
  /// `/NM` gets one, so its id changes.
  Annotation update(Pointer<fpdf_document_t__> doc, Annotation annotation) =>
      _onPage(doc, annotation.pageIndex, (page) {
        final pageIndex = annotation.pageIndex;
        final index = _find(page, pageIndex, annotation.id);
        if (index == null) {
          throw PdfEngineException(
            EngineErrorKind.unknownAnnotation,
            'Not on page $pageIndex: ${annotation.id}',
          );
        }
        final current = _readAt(page, pageIndex, index)!;
        if (current.byDoxa) {
          if (!annotation.byDoxa ||
              annotation.runtimeType != current.runtimeType) {
            throw PdfEngineException(
              EngineErrorKind.unsupportedEdit,
              'A Doxa annotation keeps its kind: ${annotation.id}',
            );
          }
          // Doxa's own annotations hold nothing Doxa did not write, so a
          // rebuild loses nothing.
          _remove(page, [index]);
          _create(page, annotation);
          final rebuilt = _find(page, pageIndex, annotation.id)!;
          return _readAt(page, pageIndex, rebuilt)!;
        }
        final annot = _pdf.FPDFPage_GetAnnot(page, index);
        try {
          _patchForeign(annot, current, annotation);
          final id = _reader.idOf(annot, pageIndex, index);
          return _reader.readOne(annot, pageIndex, index) ??
              (throw PdfEngineException(
                EngineErrorKind.documentError,
                'Cannot read back $id',
              ));
        } finally {
          _pdf.FPDFPage_CloseAnnot(annot);
        }
      });

  /// Deletes the annotations with [ids] from page [pageIndex], with the
  /// popups that belong to them. Nothing is deleted when an id is not on
  /// the page.
  void delete(
    Pointer<fpdf_document_t__> doc,
    int pageIndex,
    List<String> ids,
  ) => _onPage(doc, pageIndex, (page) {
    final indices = <int>{};
    for (final id in ids) {
      final index = _find(page, pageIndex, id);
      if (index == null) {
        throw PdfEngineException(
          EngineErrorKind.unknownAnnotation,
          'Not on page $pageIndex: $id',
        );
      }
      indices.add(index);
      final annot = _pdf.FPDFPage_GetAnnot(page, index);
      try {
        final popup = _linked(annot, 'Popup');
        if (popup != nullptr) {
          final popupIndex = _pdf.FPDFPage_GetAnnotIndex(page, popup);
          _pdf.FPDFPage_CloseAnnot(popup);
          if (popupIndex >= 0) indices.add(popupIndex);
        }
      } finally {
        _pdf.FPDFPage_CloseAnnot(annot);
      }
    }
    _remove(page, indices);
  });

  T _onPage<T>(
    Pointer<fpdf_document_t__> doc,
    int pageIndex,
    T Function(_Page page) action,
  ) {
    final count = _pdf.FPDF_GetPageCount(doc);
    if (pageIndex < 0 || pageIndex >= count) {
      throw PdfEngineException(
        EngineErrorKind.invalidPage,
        'Page $pageIndex is outside 0..${count - 1}',
      );
    }
    final page = _pdf.FPDF_LoadPage(doc, pageIndex);
    if (page == nullptr) {
      throw PdfEngineException(
        EngineErrorKind.documentError,
        'Cannot load page $pageIndex for editing',
      );
    }
    try {
      return action(page);
    } finally {
      _pdf.FPDF_ClosePage(page);
    }
  }

  /// The index of the annotation with [id], as `read` gives ids.
  int? _find(_Page page, int pageIndex, String id) {
    final count = _pdf.FPDFPage_GetAnnotCount(page);
    for (var i = 0; i < count; i++) {
      final annot = _pdf.FPDFPage_GetAnnot(page, i);
      if (annot == nullptr) continue;
      try {
        if (AnnotationReader.isSkipped(_pdf.FPDFAnnot_GetSubtype(annot))) {
          continue;
        }
        if (_reader.idOf(annot, pageIndex, i) == id) return i;
      } finally {
        _pdf.FPDFPage_CloseAnnot(annot);
      }
    }
    return null;
  }

  Annotation? _readAt(_Page page, int pageIndex, int index) {
    final annot = _pdf.FPDFPage_GetAnnot(page, index);
    try {
      return _reader.readOne(annot, pageIndex, index);
    } finally {
      _pdf.FPDFPage_CloseAnnot(annot);
    }
  }

  void _remove(_Page page, Iterable<int> indices) {
    for (final index in indices.toList()..sort((a, b) => b.compareTo(a))) {
      if (_pdf.FPDFPage_RemoveAnnot(page, index) == 0) {
        throw PdfEngineException(
          EngineErrorKind.documentError,
          'Cannot remove annotation $index',
        );
      }
    }
  }

  void _create(_Page page, Annotation annotation) {
    switch (annotation) {
      case TextMarkup():
        _createMarkup(page, annotation);
      case InkAnnotation():
        _createInk(page, annotation);
      case OtherAnnotation():
        throw PdfEngineException(
          EngineErrorKind.unsupportedEdit,
          'Doxa does not create ${annotation.subtype} annotations',
        );
    }
  }

  void _createMarkup(_Page page, TextMarkup markup) {
    final annot = _pdf.FPDFPage_CreateAnnot(page, _markupSubtype(markup.kind));
    _check(annot != nullptr, 'CreateAnnot');
    try {
      final quad = calloc<FS_QUADPOINTSF>();
      try {
        for (final q in markup.quads) {
          quad.ref
            ..x1 = q.p1.x
            ..y1 = q.p1.y
            ..x2 = q.p2.x
            ..y2 = q.p2.y
            ..x3 = q.p3.x
            ..y3 = q.p3.y
            ..x4 = q.p4.x
            ..y4 = q.p4.y;
          _check(
            _pdf.FPDFAnnot_AppendAttachmentPoints(annot, quad) != 0,
            'AppendAttachmentPoints',
          );
        }
      } finally {
        calloc.free(quad);
      }
      _setRect(annot, markup.rect);
      _setColor(annot, markup.color ?? 0xFFFF00, markup.opacity);
      _setCommon(annot, markup);
      if (markup.text case final text?) {
        _setString(annot, DoxaMarker.textKey, text);
      }
    } finally {
      _pdf.FPDFPage_CloseAnnot(annot);
    }
  }

  void _createInk(_Page page, InkAnnotation ink) {
    final annot = _pdf.FPDFPage_CreateAnnot(page, FPDF_ANNOT_INK);
    _check(annot != nullptr, 'CreateAnnot');
    try {
      for (final stroke in ink.strokes) {
        final points = calloc<FS_POINTF_>(stroke.points.length);
        try {
          for (final (i, p) in stroke.points.indexed) {
            points[i]
              ..x = p.x
              ..y = p.y;
          }
          _check(
            _pdf.FPDFAnnot_AddInkStroke(annot, points, stroke.points.length) >=
                0,
            'AddInkStroke',
          );
        } finally {
          calloc.free(points);
        }
      }
      _setRect(annot, ink.rect);
      // Every dictionary value first: SetBorder deletes an existing
      // appearance, and SetColor fails once one exists (ADR-0008).
      _check(
        _pdf.FPDFAnnot_SetBorder(annot, 0, 0, ink.width) != 0,
        'SetBorder',
      );
      final color = ink.color ?? 0x000000;
      _setColor(annot, color, ink.opacity);
      _setCommon(annot, ink);
      _setString(annot, DoxaMarker.toolKey, ink.tool.name);
      if (ink.strokes.any((s) => s.pressures != null)) {
        _setString(
          annot,
          DoxaMarker.pressureKey,
          PressureCodec.encode([
            for (final s in ink.strokes) s.pressures ?? const <double>[],
          ]),
        );
      }
      for (final stroke in ink.strokes) {
        _check(
          _pdf.FPDFAnnot_AppendObject(
                annot,
                _outlinePath(stroke, ink, color),
              ) !=
              0,
          'AppendObject',
        );
      }
    } finally {
      _pdf.FPDFPage_CloseAnnot(annot);
    }
  }

  /// One stroke's variable-width outline as a filled path; Multiply for
  /// the highlighter pen (FR-INK-004).
  Pointer<fpdf_pageobject_t__> _outlinePath(
    InkStroke stroke,
    InkAnnotation ink,
    int color,
  ) {
    final outline = strokeOutline(
      stroke.points,
      strokeWidths(stroke, ink.width, ink.tool),
      roundCaps: ink.tool == InkTool.pen,
    );
    final path = _pdf.FPDFPageObj_CreateNewPath(
      outline.first.x,
      outline.first.y,
    );
    _check(path != nullptr, 'CreateNewPath');
    for (final p in outline.skip(1)) {
      _pdf.FPDFPath_LineTo(path, p.x, p.y);
    }
    _pdf.FPDFPath_Close(path);
    _pdf.FPDFPath_SetDrawMode(path, FPDF_FILLMODE_WINDING, 0);
    _pdf.FPDFPageObj_SetFillColor(
      path,
      color >> 16 & 0xFF,
      color >> 8 & 0xFF,
      color & 0xFF,
      255,
    );
    if (ink.tool == InkTool.highlighter) {
      final mode = 'Multiply'.toNativeUtf8().cast<Char>();
      _pdf.FPDFPageObj_SetBlendMode(path, mode);
      calloc.free(mode);
    }
    return path;
  }

  /// Patches the keys of another app's annotation that [wanted] changes.
  void _patchForeign(_Annot annot, Annotation current, Annotation wanted) {
    if (wanted.byDoxa ||
        wanted.subtype != current.subtype ||
        wanted.rect != current.rect ||
        !_sameGeometry(current, wanted)) {
      throw PdfEngineException(
        EngineErrorKind.unsupportedEdit,
        'Only the colour, opacity, note, author and flags of another '
        'app\'s annotation change: ${wanted.id}',
      );
    }
    if (wanted.color != current.color || wanted.opacity != current.opacity) {
      if (_reader.hasAppearance(annot)) {
        // A markup is drawn without /AP (ADR-0008), so its appearance can
        // go; other appearances would need rebuilding.
        if (current is! TextMarkup) {
          throw PdfEngineException(
            EngineErrorKind.unsupportedEdit,
            'The appearance of ${wanted.subtype} ${wanted.id} sets its colour',
          );
        }
        _check(
          _pdf.FPDFAnnot_SetAP(
                annot,
                FPDF_ANNOT_APPEARANCEMODE_NORMAL,
                nullptr,
              ) !=
              0,
          'SetAP',
        );
      }
      _setColor(annot, wanted.color ?? 0x000000, wanted.opacity);
    }
    if (wanted.contents != current.contents) {
      _setString(annot, 'Contents', wanted.contents ?? '');
    }
    if (wanted.author != current.author) {
      _setString(annot, 'T', wanted.author ?? '');
    }
    if (wanted.flags != current.flags) {
      _check(_pdf.FPDFAnnot_SetFlags(annot, wanted.flags) != 0, 'SetFlags');
    }
    // An annotation without /NM gets one the first time it changes (03 §5).
    if (!_hasKey(annot, 'NM')) _setString(annot, 'NM', AnnotationId.generate());
    _setString(annot, 'M', formatPdfDate(wanted.modified ?? now()));
  }

  static bool _sameGeometry(Annotation a, Annotation b) => switch ((a, b)) {
    (TextMarkup a, TextMarkup b) =>
      a.kind == b.kind && _listEquals(a.quads, b.quads),
    (InkAnnotation a, InkAnnotation b) =>
      a.width == b.width &&
          a.tool == b.tool &&
          _listEquals(a.strokes, b.strokes),
    (OtherAnnotation(), OtherAnnotation()) => true,
    _ => false,
  };

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// `/NM`, `/DoxaVersion`, `/T`, `/Contents`, `/M`, `/CreationDate` and
  /// `/F` of an annotation Doxa creates.
  void _setCommon(_Annot annot, Annotation annotation) {
    _check(_pdf.FPDFAnnot_SetFlags(annot, annotation.flags) != 0, 'SetFlags');
    _setString(annot, 'NM', annotation.id);
    _setString(annot, DoxaMarker.versionKey, DoxaMarker.version);
    if (annotation.author case final author?) _setString(annot, 'T', author);
    if (annotation.contents case final contents?) {
      _setString(annot, 'Contents', contents);
    }
    final date = formatPdfDate(annotation.modified ?? now());
    _setString(annot, 'M', date);
    _setString(annot, 'CreationDate', date);
  }

  /// `/C`, and `/CA` from [opacity] (PDFium writes it with the colour).
  void _setColor(_Annot annot, int color, double opacity) => _check(
    _pdf.FPDFAnnot_SetColor(
          annot,
          FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
          color >> 16 & 0xFF,
          color >> 8 & 0xFF,
          color & 0xFF,
          (opacity.clamp(0.0, 1.0) * 255).round(),
        ) !=
        0,
    'SetColor',
  );

  void _setRect(_Annot annot, PdfRect rect) {
    final r = calloc<FS_RECTF_>();
    try {
      final n = rect.normalized();
      r.ref
        ..left = n.left
        ..bottom = n.bottom
        ..right = n.right
        ..top = n.top;
      _check(_pdf.FPDFAnnot_SetRect(annot, r) != 0, 'SetRect');
    } finally {
      calloc.free(r);
    }
  }

  void _setString(_Annot annot, String key, String value) {
    final name = key.toNativeUtf8().cast<Char>();
    final text = value.toNativeUtf16().cast<UnsignedShort>();
    try {
      _check(
        _pdf.FPDFAnnot_SetStringValue(annot, name, text) != 0,
        'SetStringValue($key)',
      );
    } finally {
      calloc
        ..free(name)
        ..free(text);
    }
  }

  bool _hasKey(_Annot annot, String key) {
    final name = key.toNativeUtf8().cast<Char>();
    try {
      return _pdf.FPDFAnnot_HasKey(annot, name) != 0;
    } finally {
      calloc.free(name);
    }
  }

  _Annot _linked(_Annot annot, String key) {
    final name = key.toNativeUtf8().cast<Char>();
    try {
      return _pdf.FPDFAnnot_GetLinkedAnnot(annot, name);
    } finally {
      calloc.free(name);
    }
  }

  static int _markupSubtype(MarkupKind kind) => switch (kind) {
    MarkupKind.highlight => FPDF_ANNOT_HIGHLIGHT,
    MarkupKind.underline => FPDF_ANNOT_UNDERLINE,
    MarkupKind.squiggly => FPDF_ANNOT_SQUIGGLY,
    MarkupKind.strikeOut => FPDF_ANNOT_STRIKEOUT,
  };

  static void _check(bool ok, String call) {
    if (!ok) {
      throw PdfEngineException(
        EngineErrorKind.documentError,
        'PDFium refused $call',
      );
    }
  }
}
