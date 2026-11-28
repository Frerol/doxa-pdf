// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_ink/doxa_ink.dart';
import 'package:flutter/foundation.dart';

/// The colour of a markup or ink without `/C`.
const defaultAnnotationColor = 0xFFD400;

/// The annotations of one open document, loaded page by page from the
/// engine (FR-ANNO-002). The reader draws Doxa's own from here; tiles hold
/// everything else (ADR-0005 §3–4).
final class DocumentAnnotations {
  DocumentAnnotations(this._engine, this._document);

  final PdfEngine _engine;
  final DocumentHandle _document;
  final _store = AnnotationStore();
  final _loads = <int, Future<void>>{};
  final _loaded = <int>{};

  /// Called with the pages whose annotations changed.
  void Function(Set<int> pages)? onChanged;

  bool isLoaded(int page) => _loaded.contains(page);

  /// Loads the annotations of [page] once. A damaged page has none.
  Future<void> load(int page) => _loads[page] ??= () async {
    List<Annotation> annotations;
    try {
      annotations = await _engine.annotations(_document, page);
    } on PdfEngineException {
      annotations = const [];
    }
    // A command may have added to the page while it loaded.
    final known = _store.page(page);
    final fresh = [
      for (final a in annotations)
        if (!known.containsKey(a.id)) a,
    ];
    if (fresh.isNotEmpty) _store.apply(AddAnnotations(fresh));
    _loaded.add(page);
    onChanged?.call({page});
  }();

  /// The annotations of [page] by id.
  Map<String, Annotation> page(int page) => _store.page(page);

  /// Doxa's own annotations of [page] that are shown, which the reader
  /// draws itself.
  Iterable<Annotation> drawn(int page) =>
      _store.page(page).values.where((a) => a.byDoxa && !a.isHidden);

  /// Applies [command] (an edit or its undo) to what the reader draws.
  void apply(AnnotationCommand command) {
    _store.apply(command);
    onChanged?.call(command.pageIndexes);
  }
}

/// The matrix from PDF user space of a page to document units, for a page
/// at [pageRect] with [transform] (which maps user space to view units
/// relative to the page's top-left corner).
Float64List userToDocumentMatrix(PageTransform transform, ui.Rect pageRect) {
  final (ox, oy) = transform.toView(const PdfPoint(0, 0));
  final (xx, xy) = transform.toView(const PdfPoint(1, 0));
  final (yx, yy) = transform.toView(const PdfPoint(0, 1));
  return Float64List.fromList([
    xx - ox, xy - oy, 0, 0, //
    yx - ox, yy - oy, 0, 0,
    0, 0, 1, 0,
    ox + pageRect.left, oy + pageRect.top, 0, 1,
  ]);
}

final _markupShapes = Expando<ui.Path>('markup shape');
final _inkShapes = Expando<ui.Path>('ink shape');

ui.Color annotationColor(Annotation annotation) {
  final rgb = annotation.color ?? defaultAnnotationColor;
  return ui.Color(0xFF000000 | rgb).withValues(alpha: annotation.opacity);
}

/// Paints [markup] in PDF user space (the canvas maps user space to the
/// screen), with Multiply so the text under it stays dark (FR-MARK-001).
void paintMarkup(ui.Canvas canvas, TextMarkup markup) {
  final path = _markupShapes[markup] ??= markupPath(markup);
  canvas.drawPath(
    path,
    ui.Paint()
      ..color = annotationColor(markup)
      ..blendMode = ui.BlendMode.multiply,
  );
}

/// The filled shape of [markup] in PDF user space: the quads of a
/// highlight, or a band along each quad for the other kinds. Each quad
/// runs p1–p2 along its top edge and p3–p4 along its bottom edge.
ui.Path markupPath(TextMarkup markup) {
  final path = ui.Path();
  for (final q in markup.quads) {
    // Fractions of the quad's height, from its bottom edge up.
    PdfPoint at(PdfPoint bottom, PdfPoint top, double f) => PdfPoint(
      bottom.x + (top.x - bottom.x) * f,
      bottom.y + (top.y - bottom.y) * f,
    );
    void band(double from, double to) => path.addPolygon([
      for (final p in [
        at(q.p3, q.p1, from),
        at(q.p4, q.p2, from),
        at(q.p4, q.p2, to),
        at(q.p3, q.p1, to),
      ])
        ui.Offset(p.x, p.y),
    ], true);
    const line = 0.08;
    switch (markup.kind) {
      case MarkupKind.highlight:
        band(0, 1);
      case MarkupKind.underline:
        band(0, line);
      case MarkupKind.strikeOut:
        band(0.5 - line / 2, 0.5 + line / 2);
      case MarkupKind.squiggly:
        _squiggle(path, q, at, line);
    }
  }
  return path;
}

/// A zigzag band along the bottom of [q], one wave per half quad height.
void _squiggle(
  ui.Path path,
  PdfQuad q,
  PdfPoint Function(PdfPoint, PdfPoint, double) at,
  double line,
) {
  final height = math.sqrt(
    math.pow(q.p1.x - q.p3.x, 2) + math.pow(q.p1.y - q.p3.y, 2),
  );
  final length = math.sqrt(
    math.pow(q.p4.x - q.p3.x, 2) + math.pow(q.p4.y - q.p3.y, 2),
  );
  if (height <= 0 || length <= 0) return;
  final steps = math.max(2, (length / (height / 4)).round());
  const amplitude = 0.12;
  PdfPoint along(double t, double f) {
    final bottom = PdfPoint(
      q.p3.x + (q.p4.x - q.p3.x) * t,
      q.p3.y + (q.p4.y - q.p3.y) * t,
    );
    final top = PdfPoint(
      q.p1.x + (q.p2.x - q.p1.x) * t,
      q.p1.y + (q.p2.y - q.p1.y) * t,
    );
    return at(bottom, top, f);
  }

  final lower = <ui.Offset>[];
  final upper = <ui.Offset>[];
  for (var i = 0; i <= steps; i++) {
    final base = i.isEven ? 0.0 : amplitude;
    final low = along(i / steps, base);
    final high = along(i / steps, base + line);
    lower.add(ui.Offset(low.x, low.y));
    upper.add(ui.Offset(high.x, high.y));
  }
  path.addPolygon([...lower, ...upper.reversed], true);
}

/// The filled outline of every stroke of [ink], in PDF user space, as one
/// path: where strokes cross, the colour is laid down once.
ui.Path inkPath(InkAnnotation ink) => _inkShapes[ink] ??= () {
  final path = ui.Path();
  for (final stroke in ink.strokes) {
    final outline = strokeOutline(
      stroke.points,
      strokeWidths(stroke, ink.width, ink.tool),
      roundCaps: ink.tool == InkTool.pen,
    );
    path.addPolygon([for (final p in outline) ui.Offset(p.x, p.y)], true);
  }
  return path;
}();

/// The paint of [ink]: the highlighter lays its colour with Multiply when
/// its layer is composited (FR-INK-004), so here both draw normally.
ui.Paint inkPaint(Annotation ink) => ui.Paint()..color = annotationColor(ink);

/// A stroke being drawn, before it becomes ink (ADR-0006): kept in PDF user
/// space of its page.
@immutable
final class LiveStroke {
  const LiveStroke({
    required this.pageIndex,
    required this.points,
    this.pressures,
    required this.width,
    this.tool = InkTool.pen,
    this.color = 0x000000,
    this.opacity = 1,
  });

  final int pageIndex;
  final List<PdfPoint> points;
  final List<double>? pressures;
  final double width;
  final InkTool tool;
  final int color;
  final double opacity;

  ui.Path path() {
    final stroke = InkStroke(points, pressures: pressures);
    final outline = strokeOutline(
      points,
      strokeWidths(stroke, width, tool),
      roundCaps: tool == InkTool.pen,
    );
    return ui.Path()
      ..addPolygon([for (final p in outline) ui.Offset(p.x, p.y)], true);
  }

  ui.Paint paint() => ui.Paint()
    ..color = ui.Color(0xFF000000 | color).withValues(alpha: opacity)
    ..blendMode = tool == InkTool.highlighter
        ? ui.BlendMode.multiply
        : ui.BlendMode.srcOver;
}
