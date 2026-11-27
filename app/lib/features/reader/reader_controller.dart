// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_geometry.dart';
import 'tile_cache.dart';

/// Turns rendered pixels into an image; injectable for tests.
typedef BitmapDecoder = Future<ui.Image> Function(RenderedBitmap bitmap);

Future<ui.Image> decodeBitmap(RenderedBitmap bitmap) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bitmap.pixels,
    bitmap.width,
    bitmap.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// A zoom and offset of the view, for page-turn animations.
typedef ViewState = ({double zoom, Offset offset, bool atFit});

typedef _Anchor = ({int page, double x, double y});

/// Where the reader is, kept across app restarts (FR-VIEW-006): a page,
/// a point of it as fractions of the page size (the top-left corner at a
/// user zoom in continuous mode, the middle otherwise), and the zoom.
/// A saved zoom of zero means to use the current fit setting.
typedef ReadingPosition = ({int page, double x, double y, double zoom});

/// Layers of rectangles drawn over the pages.
enum HighlightLayer { searchHits, currentHit, selection }

/// A history entry that survives relayouts: a reading point and a zoom.
typedef _Mark = ({_Anchor anchor, double zoom});

/// State of the reader (issues #47, #48): layout, viewport, the image cache
/// and the render requests sent to the engine.
///
/// The view is `screen = (document - offset) * zoom`, in document units
/// (see [PageLayout]). At zoom 1 pages fit the screen as their layout
/// defines (the width in continuous mode, the whole spread when paged).
/// Pan and zoom only change numbers and bump [repaint]; nothing is rebuilt
/// (ADR-0006).
final class ReaderController {
  ReaderController({
    required this.engine,
    required this.document,
    required this.info,
    BitmapDecoder decoder = decodeBitmap,
    int cacheBudgetBytes = 160 << 20,
    ReaderOptions options = const ReaderOptions(),
    ReadingPosition? initialPosition,
    FitMode fitMode = FitMode.page,
    bool zoomOutPastFit = false,
  }) : _decode = decoder,
       _options = options, // ignore: prefer_initializing_formals
       _initial = initialPosition,
       _fitMode = fitMode, // ignore: prefer_initializing_formals
       _zoomOutPastFit = zoomOutPastFit, // ignore: prefer_initializing_formals
       cache = TileCache(budgetBytes: cacheBudgetBytes);

  static const minZoom = 0.25;
  static const maxZoom = 8.0;

  /// Zoom used by the smart double tap (FR-VIEW-004).
  static const smartZoomLevel = 2.5;

  final PdfEngine engine;
  final DocumentHandle document;
  final DocumentInfo info;
  final TileCache cache;
  final BitmapDecoder _decode;

  /// Bumped whenever the picture changes.
  final repaint = ValueNotifier<int>(0);

  /// The page under the middle of the screen, for page indicators.
  final page = ValueNotifier<int>(0);

  /// Bumped when [canGoBack] or [canGoForward] change.
  final history = ValueNotifier<int>(0);
  final _back = <_Mark>[];
  final _forward = <_Mark>[];

  final _details = <int, Future<PageDetails>>{};
  final _resolvedDetails = <int, PageDetails>{};
  final _layers = <HighlightLayer, Map<int, List<PdfRect>>>{};
  final _links = <int, Future<List<PageLink>>>{};

  ReaderOptions _options;

  /// Shown by the first layout, then dropped.
  ReadingPosition? _initial;
  PageLayout? _layout;
  Size _viewSize = Size.zero;
  double _devicePixelRatio = 1;
  double _zoom = 1;
  FitMode _fitMode;
  bool _zoomOutPastFit;
  bool _atFit = true;
  double _ox = 0;
  double _oy = 0;
  int _generation = 0;

  /// Bumped on every new layout: renders requested for an older layout
  /// have the wrong geometry and are dropped.
  int _layoutEpoch = 0;

  /// Newest request per key: its generation, and whether a new generation
  /// keeps it (see [RenderPriority.keptWhenStale]).
  final _pending = <String, ({int generation, bool kept})>{};
  var _disposed = false;

  ReaderOptions get options => _options;
  PageLayout? get layout => _layout;
  Size get viewSize => _viewSize;
  double get devicePixelRatio => _devicePixelRatio;
  double get zoom => _zoom;

  /// Whether the view follows the fit mode when the viewport changes.
  bool get atFit => _atFit;

  Offset get offset => Offset(_ox, _oy);
  int get pendingRequests => _pending.length;

  /// The visible part of the document, in document units.
  Rect get visibleRect => Rect.fromLTWH(
    _ox,
    _oy,
    _viewSize.width / _zoom,
    _viewSize.height / _zoom,
  );

  /// The page under the middle of the screen.
  int get currentPage => _layout?.pageAt(visibleRect.center) ?? 0;

  /// The spread under the middle of the screen.
  int get currentSpread => _layout?.spreadOf(currentPage) ?? 0;

  double get bucket => zoomBucket(_zoom);

  Offset toDocument(Offset screen) =>
      Offset(_ox + screen.dx / _zoom, _oy + screen.dy / _zoom);

  bool _keepScale = false;

  /// Makes the next [resize] keep a user zoom's page size on screen instead
  /// of its zoom relative to fit. The side panel calls it as it docks or
  /// undocks (UX §7); a rotation keeps the relative zoom.
  void keepScaleOnNextResize() => _keepScale = true;

  /// Lays the document out for a new view size, keeping the reading
  /// position.
  void resize(Size size, double devicePixelRatio) {
    if (size.width <= 0 || size.height <= 0) return;
    if (size == _viewSize && devicePixelRatio == _devicePixelRatio) return;
    final old = _layout;
    final relayout =
        old == null ||
        size.width != _viewSize.width ||
        devicePixelRatio != _devicePixelRatio ||
        (old.usesViewHeight && size.height != _viewSize.height);
    final anchor = _anchor();
    _viewSize = size;
    _devicePixelRatio = devicePixelRatio;
    if (relayout) _relayout();
    // After [keepScaleOnNextResize], a user zoom keeps the page's size on
    // screen: the layout scales with the view width, so the zoom makes up
    // for it, and a narrower view clips the page instead of shrinking it.
    final keepScale = _keepScale;
    _keepScale = false;
    final layout = _layout;
    if (keepScale &&
        !_atFit &&
        old != null &&
        anchor != null &&
        layout != null) {
      final before = old.pageRect(anchor.page).width;
      final after = layout.pageRect(anchor.page).width;
      if (before > 0 && after > 0) {
        _zoom = (_zoom * before / after).clamp(minZoom, maxZoom);
      }
    }
    _restore(old == null ? _takeInitial() : anchor);
    _changed();
  }

  /// Switches layout or page-turning options (FR-VIEW-002, FR-VIEW-003,
  /// FR-VIEW-017..019), keeping the current page.
  void setOptions(ReaderOptions options) {
    if (options == _options) return;
    final layoutChanged =
        options.mode != _options.mode ||
        options.rightToLeft != _options.rightToLeft ||
        options.coverPage != _options.coverPage;
    _options = options;
    if (!layoutChanged || _layout == null) return;
    final current = currentPage;
    _relayout();
    _atFit = true;
    _showPage(current);
    _changed();
  }

  void _relayout() {
    _layout = buildLayout(info, _options, _viewSize);
    // Tiles depend on the page size in pixels: drop those of the old layout.
    _layoutEpoch++;
    _pending.removeWhere((key, _) => key.startsWith('t:'));
    cache.removeWhere((key) => key.startsWith('t:'));
  }

  /// The reading position: a page and a point of it, as fractions of the
  /// page size. A continuous view at a user zoom uses its top-left corner;
  /// other views use the middle of the screen.
  _Anchor? _anchor() {
    final layout = _layout;
    if (layout == null || layout.pageCount == 0) return null;
    final visible = visibleRect;
    final point = layout is ContinuousLayout && !_atFit
        ? visible.topLeft
        : visible.center;
    final page = layout.pageAt(point);
    final rect = layout.pageRect(page);
    return (
      page: page,
      x: (point.dx - rect.left) / rect.width,
      y: (point.dy - rect.top) / rect.height,
    );
  }

  void _restore(_Anchor? anchor) {
    final layout = _layout!;
    if (layout.pageCount == 0) return;
    if (anchor == null) {
      // First layout: start at the first page, which is the rightmost cell
      // when reading right to left.
      _showPage(0);
      return;
    }
    if (_atFit) {
      _showPage(anchor.page);
      if (layout is ContinuousLayout && _fitMode == FitMode.width) {
        final rect = layout.pageRect(anchor.page);
        _oy = rect.top + anchor.y * rect.height - visibleRect.height / 2;
      }
      return;
    }
    final rect = layout.pageRect(anchor.page);
    final point = Offset(
      rect.left + anchor.x * rect.width,
      rect.top + anchor.y * rect.height,
    );
    if (layout is ContinuousLayout) {
      _ox = point.dx;
      _oy = point.dy;
    } else {
      // Keep the zoom and put the same point back in the middle.
      _ox = point.dx - _viewSize.width / _zoom / 2;
      _oy = point.dy - _viewSize.height / _zoom / 2;
    }
  }

  /// Moves the view by a screen-space [delta] (a finger drag).
  void panBy(Offset delta) {
    _ox -= delta.dx / _zoom;
    _oy -= delta.dy / _zoom;
    _changed();
  }

  /// The smallest zoom a pinch reaches: the chosen fit of the page or
  /// spread on screen, or [minZoom] when zooming out past it is allowed
  /// (#120). Below the fit, a single page would show its neighbours.
  double get lowestZoom {
    final layout = _layout;
    if (_zoomOutPastFit ||
        layout == null ||
        layout.pageCount == 0 ||
        _viewSize.isEmpty) {
      return minZoom;
    }
    return _fitView(currentSpread).zoom.clamp(minZoom, maxZoom);
  }

  /// Sets the zoom so that [documentPoint] stays under [screenPoint]. At
  /// [lowestZoom] the view goes back to the fit of the current page.
  void zoomAround(double zoom, Offset documentPoint, Offset screenPoint) {
    final lowest = lowestZoom;
    if (!_zoomOutPastFit && zoom < lowest * (1 - 1e-9)) {
      if (_layout is! ContinuousLayout) {
        _fitCurrentPage();
        return;
      }
      // A continuous view keeps its scroll position under the fingers.
      final fit = _fitView(currentSpread);
      _atFit = true;
      _zoom = fit.zoom;
      _ox = fit.offset.dx;
      _oy = documentPoint.dy - screenPoint.dy / _zoom;
      _changed();
      return;
    }
    _atFit = false;
    _zoom = zoom.clamp(lowest, maxZoom);
    _ox = documentPoint.dx - screenPoint.dx / _zoom;
    _oy = documentPoint.dy - screenPoint.dy / _zoom;
    _changed();
  }

  /// Sets a user zoom around the middle of the screen.
  void zoomTo(double zoom) {
    final centre = _viewSize.center(Offset.zero);
    zoomAround(zoom, toDocument(centre), centre);
  }

  /// Changes the fit preference, immediately re-fitting a view at fit.
  void setFitMode(FitMode mode) {
    if (_fitMode == mode) return;
    _fitMode = mode;
    if (_atFit) _fitCurrentPage();
  }

  /// Allows or stops zooming out past the fit (#120). A view below the fit
  /// goes back to it when the limit returns.
  void setZoomOutPastFit(bool allowed) {
    if (_zoomOutPastFit == allowed) return;
    _zoomOutPastFit = allowed;
    if (!allowed && !_atFit && _zoom < lowestZoom) _fitCurrentPage();
  }

  /// Fits the current page or spread to the viewport width.
  void fitWidth() {
    _fitMode = FitMode.width;
    _fitCurrentPage();
  }

  /// Fits the whole current page or spread in the viewport.
  void fitPage() {
    _fitMode = FitMode.page;
    _fitCurrentPage();
  }

  void _fitCurrentPage() {
    final layout = _layout;
    if (layout == null || layout.pageCount == 0) return;
    _atFit = true;
    _showPage(currentPage);
    _changed();
  }

  ViewState _fitView(int spread) {
    final layout = _layout!;
    final cell = layout.spreadRect(spread);
    var bounds = cell;
    if (_fitMode == FitMode.width) {
      bounds = layout
          .pagesOf(spread)
          .map(layout.pageRect)
          .reduce((first, second) => first.expandToInclude(second));
    }
    final widthZoom = _viewSize.width / bounds.width;
    final zoom = _fitMode == FitMode.width
        ? widthZoom
        : math.min(widthZoom, _viewSize.height / bounds.height);
    final centered = bounds.center - _viewSize.center(Offset.zero) / zoom;
    return (
      zoom: zoom,
      offset:
          _fitMode == FitMode.width && bounds.height * zoom > _viewSize.height
          ? Offset(centered.dx, bounds.top)
          : centered,
      atFit: true,
    );
  }

  /// Double tap (FR-VIEW-004): zoom in relative to fit at the tapped point,
  /// or return to the chosen fit mode.
  void smartZoom(Offset screenPoint) {
    final layout = _layout;
    if (layout == null || layout.pageCount == 0) return;
    final point = toDocument(screenPoint);
    if (_atFit) {
      zoomAround(_zoom * smartZoomLevel, point, screenPoint);
    } else {
      _atFit = true;
      _showPage(layout.pageAt(point));
      _changed();
    }
  }

  /// Shows [page]: at the top of the screen in continuous mode, or its
  /// spread when paged.
  ///
  /// With [record], the jump can be undone with [goBack] (FR-VIEW-011).
  void goToPage(int page, {bool record = false}) {
    final layout = _layout;
    if (layout == null || page < 0 || page >= layout.pageCount) return;
    if (record && page != currentPage) _record();
    _showPage(page);
    _changed();
  }

  /// The label of [page] (FR-VIEW-014), or its 1-based number when the
  /// document has none.
  String pageLabel(int page) => info.pageLabels[page] ?? '${page + 1}';

  /// The page a user typed in "Go to page" (FR-VIEW-009): a page label
  /// such as `iv` or `A-1` first, then a 1-based page number. Null when
  /// nothing matches.
  int? parsePageInput(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    for (var i = 0; i < info.pageCount; i++) {
      if (info.pageLabels[i]?.toLowerCase() == lower) return i;
    }
    final number = int.tryParse(text);
    if (number == null || number < 1 || number > info.pageCount) return null;
    return number - 1;
  }

  /// Crop box and rotation of [page], loaded once.
  Future<PageDetails> pageDetails(int page) => _details[page] ??= engine
      .pageDetails(document, page)
      .then((details) => _resolvedDetails[page] = details);

  /// [rect] of [page] (PDF user space) in document units, or null until the
  /// page's details have loaded.
  Rect? documentRect(int page, PdfRect rect) {
    final layout = _layout;
    final details = _resolvedDetails[page];
    if (layout == null || details == null || page >= layout.pageCount) {
      return null;
    }
    final pageRect = layout.pageRect(page);
    final transform = _transform(details, pageRect);
    if (transform == null) return null;
    final (x1, y1) = transform.toView(PdfPoint(rect.left, rect.bottom));
    final (x2, y2) = transform.toView(PdfPoint(rect.right, rect.top));
    return Rect.fromPoints(
      Offset(x1, y1),
      Offset(x2, y2),
    ).shift(pageRect.topLeft);
  }

  /// A point in document units mapped to PDF user space of [page], or null
  /// until the page's details have loaded.
  PdfPoint? userPoint(int page, Offset documentPoint) {
    final layout = _layout;
    final details = _resolvedDetails[page];
    if (layout == null || details == null) return null;
    final pageRect = layout.pageRect(page);
    final transform = _transform(details, pageRect);
    return transform?.toUser(
      documentPoint.dx - pageRect.left,
      documentPoint.dy - pageRect.top,
    );
  }

  /// Rectangles of [layer] on [page], in PDF user space.
  List<PdfRect> highlights(HighlightLayer layer, int page) =>
      _layers[layer]?[page] ?? const [];

  /// Replaces [layer] (rectangles per page, PDF user space) and repaints
  /// once the pages' details are known.
  void setHighlights(HighlightLayer layer, Map<int, List<PdfRect>> rects) {
    if (_disposed) return;
    if (rects.isEmpty) {
      if (_layers.remove(layer) != null) repaint.value++;
      return;
    }
    _layers[layer] = rects;
    _loadVisibleDetails();
    repaint.value++;
  }

  /// Loads the details of visible pages that have highlights, so they can
  /// be drawn; pages off screen load when they scroll in.
  void _loadVisibleDetails() {
    final layout = _layout;
    if (layout == null || _layers.isEmpty) return;
    for (final page in layout.pagesIn(visibleRect)) {
      if (_resolvedDetails.containsKey(page)) continue;
      if (!_layers.values.any((rects) => rects.containsKey(page))) continue;
      unawaited(
        pageDetails(page).then((_) {
          if (!_disposed) repaint.value++;
        }, onError: (Object _) {}),
      );
    }
  }

  /// Scrolls so that [rect] of [page] is on screen, keeping the zoom (search
  /// results, FR-TEXT-001). Paged layouts show its spread.
  Future<void> reveal(int page, PdfRect rect) async {
    if (_layout == null || page < 0 || page >= info.pageCount) return;
    try {
      await pageDetails(page);
    } on PdfEngineException {
      // Fall back to showing the page.
    }
    final layout = _layout;
    if (_disposed || layout == null) return;
    final target = documentRect(page, rect);
    if (layout.paged && layout.spreadOf(page) != currentSpread) {
      final view = viewForSpread(layout.spreadOf(page), keepZoom: true);
      _applyView(view);
    }
    if (target == null) {
      if (!layout.paged) _showPage(page);
      _changed();
      return;
    }
    final visible = visibleRect;
    if (!visible.deflate(8 / _zoom).contains(target.center)) {
      if (layout is ContinuousLayout || _zoom > 1.05) {
        _oy = target.center.dy - visible.height / 2;
      }
      if (layout is! ContinuousLayout || _zoom > 1.05) {
        _ox = target.center.dx - visible.width / 2;
      }
    }
    _changed();
  }

  /// The transform from PDF user space of [page] to document units
  /// relative to the page's top-left corner, or null for a degenerate page.
  PageTransform? _transform(PageDetails details, Rect rect) {
    final (viewWidth, _) = details.transform().viewSize;
    final scale = rect.width / viewWidth;
    if (!scale.isFinite || scale <= 0) return null;
    return details.transform(scale: scale);
  }

  /// Maps a destination point in PDF user space to document units. A
  /// missing coordinate means "the start of the page" along its own axis,
  /// which a rotated page turns sideways or upside down.
  Future<Offset> _documentPoint(int page, double? x, double? y) async {
    final details = await pageDetails(page);
    final rect = _layout!.pageRect(page);
    final transform = _transform(details, rect);
    if (transform == null) return rect.topLeft;
    final crop = details.cropBox;
    var (vx, vy) = transform.toView(PdfPoint(x ?? crop.left, y ?? crop.top));
    final sideways = details.rotation == 90 || details.rotation == 270;
    // User x runs along the view's x axis unless the page is turned.
    if (x == null) sideways ? vy = 0 : vx = 0;
    if (y == null) sideways ? vx = 0 : vy = 0;
    return rect.topLeft + Offset(vx, vy);
  }

  /// The link under [screenPoint], if any (FR-VIEW-010).
  Future<LinkTarget?> linkAt(Offset screenPoint) async {
    final layout = _layout;
    if (layout == null || layout.pageCount == 0) return null;
    final point = toDocument(screenPoint);
    final page = layout.pageAt(point);
    final rect = layout.pageRect(page);
    if (!rect.contains(point)) return null;
    try {
      final details = await pageDetails(page);
      final links = await (_links[page] ??= engine.pageLinks(document, page));
      final transform = _transform(details, rect);
      if (transform == null) return null;
      final user = transform.toUser(point.dx - rect.left, point.dy - rect.top);
      for (final link in links) {
        if (link.rect.contains(user)) return link.target;
      }
    } on PdfEngineException {
      // A damaged page has no usable links.
    }
    return null;
  }

  /// Jumps to an outline entry or link target inside the document, so that
  /// [goBack] returns here (FR-VIEW-007, FR-VIEW-010, FR-VIEW-011).
  Future<void> goToDestination(PdfDestination destination) async {
    final page = destination.pageIndex;
    if (_layout == null || page < 0 || page >= info.pageCount) return;
    Offset? point;
    try {
      point = await _documentPoint(page, destination.x, destination.y);
    } on PdfEngineException {
      point = null;
    }
    // The layout may have changed while the page details loaded.
    final layout = _layout;
    if (_disposed || layout == null) return;
    point ??= layout.pageRect(page).topLeft;
    _record();
    if (layout.paged || (destination.x == null && destination.y == null)) {
      _showPage(page);
    } else if (layout is ContinuousLayout) {
      _oy = point.dy;
      if (destination.x != null && _zoom > 1) _ox = point.dx;
    } else {
      _ox = point.dx;
    }
    _changed();
  }

  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;

  /// Returns to where the reader was before the last jump.
  void goBack() => _travel(_back, _forward);

  /// Undoes [goBack].
  void goForward() => _travel(_forward, _back);

  void _travel(List<_Mark> from, List<_Mark> to) {
    final here = _mark();
    if (from.isEmpty || here == null) return;
    to.add(here);
    final mark = from.removeLast();
    history.value++;
    _restoreZoom(mark.zoom);
    _restore(mark.anchor);
    _changed();
  }

  /// The current reading position, or null before the first layout.
  ReadingPosition? get position {
    final mark = _mark();
    if (mark == null) return _initial;
    final (:anchor, :zoom) = mark;
    return (page: anchor.page, x: anchor.x, y: anchor.y, zoom: zoom);
  }

  /// The saved position as an anchor, with its zoom applied, or null when
  /// there is none or it no longer fits the document.
  _Anchor? _takeInitial() {
    final initial = _initial;
    _initial = null;
    if (initial == null ||
        initial.page < 0 ||
        initial.page >= info.pageCount ||
        !initial.zoom.isFinite) {
      return null;
    }
    _restoreZoom(initial.zoom);
    return (
      page: initial.page,
      x: initial.x.isFinite ? initial.x.clamp(0, 1) : 0,
      y: initial.y.isFinite ? initial.y.clamp(0, 1) : 0,
    );
  }

  void _restoreZoom(double zoom) {
    _atFit = zoom == fitReadingZoom || zoom < lowestZoom;
    if (!_atFit) _zoom = zoom.clamp(minZoom, maxZoom);
  }

  _Mark? _mark() {
    final anchor = _anchor();
    return anchor == null
        ? null
        : (anchor: anchor, zoom: _atFit ? fitReadingZoom : _zoom);
  }

  /// Remembers the reading position before a jump.
  void _record() {
    final here = _mark();
    if (here == null) return;
    _back.add(here);
    if (_back.length > 100) _back.removeAt(0);
    _forward.clear();
    history.value++;
  }

  /// The preview of [page] for the thumbnails panel (FR-VIEW-008), or null
  /// while it renders.
  ui.Image? thumbnail(int page) {
    final layout = _layout;
    if (layout == null || page < 0 || page >= layout.pageCount) return null;
    final spec = previewFor(layout, page);
    final image = cache.peek(spec.key);
    if (image == null) _request(spec, RenderPriority.thumbnail);
    return image;
  }

  void _showPage(int page) {
    final layout = _layout!;
    if (layout.pageCount == 0) return;
    final spread = layout.spreadOf(page);
    if (_atFit || layout.paged) {
      _applyView(viewForSpread(spread, keepZoom: true));
    } else if (layout is ContinuousLayout) {
      _oy = layout.pageRect(page).top;
    } else {
      _ox = layout.spreadRect(spread).left;
    }
  }

  /// Applies a view computed by [viewForSpread] or [settle]; used by
  /// page-turn animations.
  void setView(ViewState view) {
    _applyView(view);
    _changed();
  }

  void _applyView(ViewState view) {
    _atFit = view.atFit;
    _zoom = view.zoom;
    _ox = view.offset.dx;
    _oy = view.offset.dy;
  }

  /// The view showing [spread] in a paged layout. With [keepZoom], a user
  /// zoom and the position inside the cell stay as they are (FR-VIEW-018).
  ViewState viewForSpread(int spread, {required bool keepZoom}) {
    if (!keepZoom || _atFit) return _fitView(spread);
    final layout = _layout!;
    final cell = layout.spreadRect(spread);
    final current = layout.spreadRect(currentSpread);
    return _userViewInCell(cell, cell.topLeft + offset - current.topLeft);
  }

  ViewState _userViewInCell(Rect cell, Offset target) {
    final visible = visibleRect;
    double place(double value, double start, double end, double extent) =>
        extent >= end - start
        ? (start + end - extent) / 2
        : value.clamp(start, end - extent);
    return (
      zoom: _zoom,
      offset: Offset(
        place(target.dx, cell.left, cell.right, visible.width),
        place(target.dy, cell.top, cell.bottom, visible.height),
      ),
      atFit: false,
    );
  }

  /// Turns the page in a paged layout, towards the left or right of the
  /// screen (FR-VIEW-017, FR-VIEW-019). Returns the view to animate to, or
  /// null at the first or last spread.
  ViewState? turn({required bool towardsLeft}) {
    final layout = _layout;
    if (layout == null || !layout.paged) return null;
    final next = layout.spreadBeside(currentSpread, towardsLeft: towardsLeft);
    if (next == null) return null;
    return viewForSpread(next, keepZoom: _options.keepZoomOnTurn);
  }

  /// Turns to the next or previous page in reading order.
  ViewState? turnPage({required bool forward}) =>
      turn(towardsLeft: forward == _options.rightToLeft);

  /// Where a paged view settles after a gesture that started on
  /// [startSpread] and ended with [velocity] (screen pixels per second): a
  /// quick swipe turns one page, a slow drag stays on the spread under the
  /// middle of the screen. Returns null when nothing needs to move.
  ViewState? settle({required int startSpread, required Offset velocity}) {
    final layout = _layout;
    if (layout == null || !layout.paged || layout.spreadCount == 0) return null;
    var target = currentSpread;
    final zoomedIn = !_atFit && _zoom > 1.05;
    if (target == startSpread && !zoomedIn && velocity.dx.abs() > 600) {
      // A finger moving right reveals the spread on the left.
      target =
          layout.spreadBeside(startSpread, towardsLeft: velocity.dx > 0) ??
          startSpread;
    }
    final view = target == startSpread
        ? _clampedToCell(target)
        : viewForSpread(target, keepZoom: _options.keepZoomOnTurn);
    final same =
        view.atFit == _atFit &&
        (view.zoom - _zoom).abs() < 1e-6 &&
        (view.offset - offset).distance < 0.5;
    return same ? null : view;
  }

  /// The current view moved back inside the cell of [spread].
  ViewState _clampedToCell(int spread) {
    final cell = _layout!.spreadRect(spread);
    if (!_atFit) return _userViewInCell(cell, offset);
    final fit = _fitView(spread);
    if (_fitMode == FitMode.width && visibleRect.height < cell.height) {
      final y = _oy.clamp(cell.top, cell.bottom - visibleRect.height);
      return (zoom: fit.zoom, offset: Offset(fit.offset.dx, y), atFit: true);
    }
    return fit;
  }

  /// Frees memory on memory pressure (`onTrimMemory`): keeps only what is
  /// on screen.
  void trimMemory() {
    cache.evict(keep: visibleKeys(), targetBytes: 0);
    repaint.value++;
  }

  /// Keys of the images the screen shows now.
  Set<String> visibleKeys() {
    final layout = _layout;
    if (layout == null) return const {};
    final visible = visibleRect;
    return {
      for (final page in layout.pagesIn(visible)) ...[
        'p:$page',
        for (final tile in _tiles(page, visible)) tile.key,
      ],
    };
  }

  Iterable<TileSpec> _tiles(int page, Rect area) => tilesFor(
    _layout!,
    page,
    bucket: bucket,
    devicePixelRatio: _devicePixelRatio,
    visible: area,
  );

  /// Tiles of [page] at the current bucket inside the screen; for painting.
  Iterable<TileSpec> visibleTiles(int page) => _tiles(page, visibleRect);

  void _changed() {
    _clamp();
    _ensure();
    repaint.value++;
    _publishPage();
  }

  bool _pagePending = false;

  /// Updates [page]. [resize] runs while the view is laid out, when
  /// listeners must not rebuild, so the new page is published after that
  /// frame (a restored position or a rotation can change it).
  void _publishPage() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      page.value = currentPage;
      return;
    }
    if (_pagePending) return;
    _pagePending = true;
    binding.addPostFrameCallback((_) {
      _pagePending = false;
      if (!_disposed) page.value = currentPage;
    });
  }

  void _clamp() {
    final layout = _layout;
    if (layout == null) return;
    final visible = visibleRect;
    final content = layout.contentSize;
    _ox = visible.width >= content.width
        ? -(visible.width - content.width) / 2
        : _ox.clamp(0, content.width - visible.width);
    if (layout.paged && layout.pageCount > 0) {
      // Up and down, a paged view moves only within its pages: a page that
      // fits stays still, even when its screen-sized cell is a little
      // taller than the view (fit width). Sideways moves turn pages.
      final pages = layout
          .pagesOf(layout.spreadOf(layout.pageAt(visible.center)))
          .map(layout.pageRect)
          .reduce((first, second) => first.expandToInclude(second));
      _oy = visible.height >= pages.height
          ? pages.center.dy - visible.height / 2
          : _oy.clamp(pages.top, pages.bottom - visible.height);
      return;
    }
    _oy = visible.height >= content.height
        ? -(visible.height - content.height) / 2
        : _oy.clamp(0, content.height - visible.height);
  }

  /// Asks the engine for what the screen needs, most urgent first: visible
  /// previews, visible tiles, then one screen ahead in both directions.
  void _ensure() {
    final layout = _layout;
    if (_disposed || layout == null || layout.pageCount == 0) return;
    _generation++;
    engine.setGeneration(document, _generation);
    final visible = visibleRect;
    // One screen ahead in both directions of the layout.
    final near = layout is ContinuousLayout
        ? Rect.fromLTRB(
            visible.left,
            visible.top - visible.height,
            visible.right,
            visible.bottom + visible.height,
          )
        : Rect.fromLTRB(
            visible.left - visible.width,
            visible.top,
            visible.right + visible.width,
            visible.bottom,
          );
    final visiblePages = layout.pagesIn(visible).toList();
    _loadVisibleDetails();
    for (final page in visiblePages) {
      _request(previewFor(layout, page), RenderPriority.visiblePreview);
    }
    for (final page in visiblePages) {
      for (final tile in _tiles(page, visible)) {
        _request(tile, RenderPriority.visibleTile);
      }
    }
    final nearPages = layout.pagesIn(near).toList();
    for (final page in nearPages) {
      _request(previewFor(layout, page), RenderPriority.nearPreview);
    }
    for (final page in nearPages) {
      for (final tile in _tiles(page, near)) {
        _request(tile, RenderPriority.nearTile);
      }
    }
  }

  void _request(TileSpec spec, RenderPriority priority) {
    if (cache.use(spec.key) != null) return;
    // A request from an older generation will be dropped as stale, so ask
    // again for anything that is still needed now.
    final pending = _pending[spec.key];
    if (pending != null &&
        (pending.generation == _generation || pending.kept)) {
      return;
    }
    _pending[spec.key] = (
      generation: _generation,
      kept: priority.keptWhenStale,
    );
    final request = spec.request(
      document,
      priority: priority,
      generation: _generation,
    );
    unawaited(_load(spec.key, request, _layoutEpoch));
  }

  Future<void> _load(String key, RenderRequest request, int epoch) async {
    try {
      final result = await engine.render(request);
      if (_disposed || result is! RenderedBitmap) return;
      final image = await _decode(result);
      if (_disposed || (epoch != _layoutEpoch && key.startsWith('t:'))) {
        image.dispose();
        return;
      }
      cache.put(key, image);
      cache.evict(keep: visibleKeys());
      repaint.value++;
    } on Object catch (error) {
      // A damaged page stays blank; the rest of the document still reads.
      if (!_disposed) debugPrint('Doxa: render of $key failed: $error');
    } finally {
      if (_pending[key]?.generation == request.generation) {
        _pending.remove(key);
      }
    }
  }

  void dispose() {
    _disposed = true;
    cache.clear();
    repaint.dispose();
    page.dispose();
    history.dispose();
  }
}
