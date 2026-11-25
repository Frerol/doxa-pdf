// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
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
typedef ViewState = ({double zoom, Offset offset});

typedef _Anchor = ({int page, double x, double y});

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
  }) : _decode = decoder,
       _options = options, // ignore: prefer_initializing_formals
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
  final _links = <int, Future<List<PageLink>>>{};

  ReaderOptions _options;
  PageLayout? _layout;
  Size _viewSize = Size.zero;
  double _devicePixelRatio = 1;
  double _zoom = 1;
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

  /// Lays the document out for a new view size, keeping the reading
  /// position.
  void resize(Size size, double devicePixelRatio) {
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
    if (size.width <= 0 || size.height <= 0) return;
    if (relayout) {
      _relayout();
      _restore(anchor);
    }
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
    _zoom = 1;
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
  /// page size. In continuous mode the point is the top-left corner of the
  /// screen; otherwise it is the middle of the screen.
  _Anchor? _anchor() {
    final layout = _layout;
    if (layout == null || layout.pageCount == 0) return null;
    final visible = visibleRect;
    final point = layout is ContinuousLayout ? visible.topLeft : visible.center;
    final page = layout is ContinuousLayout
        ? layout.pageAtY(point.dy)
        : layout.pageAt(point);
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
    final rect = layout.pageRect(anchor.page);
    final point = Offset(
      rect.left + anchor.x * rect.width,
      rect.top + anchor.y * rect.height,
    );
    if (layout is ContinuousLayout) {
      _ox = point.dx;
      _oy = point.dy;
    } else if (layout.paged && _zoom <= 1) {
      _showPage(anchor.page);
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

  /// Sets the zoom so that [documentPoint] stays under [screenPoint].
  void zoomAround(double zoom, Offset documentPoint, Offset screenPoint) {
    _zoom = zoom.clamp(minZoom, maxZoom);
    _ox = documentPoint.dx - screenPoint.dx / _zoom;
    _oy = documentPoint.dy - screenPoint.dy / _zoom;
    _changed();
  }

  /// Zooms around the middle of the screen (zoom presets).
  void zoomTo(double zoom) {
    final centre = _viewSize.center(Offset.zero);
    zoomAround(zoom, toDocument(centre), centre);
  }

  /// Fit width: the current page is as wide as the screen.
  void fitWidth() {
    final layout = _layout;
    if (layout == null || layout.pageCount == 0) return;
    final rect = layout.pageRect(currentPage);
    final centreY = visibleRect.center.dy;
    _zoom = (_viewSize.width / rect.width).clamp(minZoom, maxZoom);
    _ox = rect.left;
    _oy = layout is ContinuousLayout
        ? centreY - _viewSize.height / _zoom / 2
        : rect.top;
    _changed();
  }

  /// Fit page: the current page (the spread, when paged) fits the screen,
  /// centred.
  void fitPage() {
    final layout = _layout;
    if (layout == null || layout.pageCount == 0) return;
    final rect = layout.paged
        ? layout.spreadRect(currentSpread)
        : layout.pageRect(currentPage);
    _zoom = math
        .min(_viewSize.width / rect.width, _viewSize.height / rect.height)
        .clamp(minZoom, maxZoom);
    _ox = rect.center.dx - _viewSize.width / _zoom / 2;
    _oy = rect.center.dy - _viewSize.height / _zoom / 2;
    _changed();
  }

  /// Double tap (FR-VIEW-004): zoom in on the tapped point, or back to the
  /// layout's fit when already zoomed in.
  void smartZoom(Offset screenPoint) {
    final layout = _layout;
    if (layout == null) return;
    if (_zoom > 1.05) {
      final point = toDocument(screenPoint);
      _zoom = 1;
      if (layout.paged) {
        _showPage(layout.pageAt(point));
      } else {
        // Keep the tapped point under the finger; clamping does the rest.
        _ox = point.dx - screenPoint.dx;
        _oy = point.dy - screenPoint.dy;
      }
      _changed();
    } else {
      zoomAround(smartZoomLevel, toDocument(screenPoint), screenPoint);
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
  Future<PageDetails> pageDetails(int page) =>
      _details[page] ??= engine.pageDetails(document, page);

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
    _zoom = mark.zoom.clamp(minZoom, maxZoom);
    _restore(mark.anchor);
    _changed();
  }

  _Mark? _mark() {
    final anchor = _anchor();
    return anchor == null ? null : (anchor: anchor, zoom: _zoom);
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
    switch (layout) {
      case ContinuousLayout():
        _oy = layout.pageRect(page).top;
      case _ when layout.paged:
        final view = viewForSpread(layout.spreadOf(page), keepZoom: false);
        _zoom = view.zoom;
        _ox = view.offset.dx;
        _oy = view.offset.dy;
      case _:
        _ox = layout.spreadRect(layout.spreadOf(page)).left;
    }
  }

  /// Applies a view computed by [viewForSpread] or [settle]; used by
  /// page-turn animations.
  void setView(ViewState view) {
    _zoom = view.zoom.clamp(minZoom, maxZoom);
    _ox = view.offset.dx;
    _oy = view.offset.dy;
    _changed();
  }

  /// The view showing [spread] in a paged layout. With [keepZoom], the zoom
  /// and the position inside the cell stay as they are (FR-VIEW-018).
  ViewState viewForSpread(int spread, {required bool keepZoom}) {
    final layout = _layout!;
    final cell = layout.spreadRect(spread);
    if (!keepZoom || _zoom <= 1) {
      return (zoom: 1.0, offset: cell.topLeft);
    }
    final current = layout.spreadRect(currentSpread);
    final visible = visibleRect;
    final dx = (_ox - current.left).clamp(0.0, cell.width - visible.width);
    final dy = (_oy - current.top).clamp(0.0, cell.height - visible.height);
    return (zoom: _zoom, offset: cell.topLeft + Offset(dx, dy));
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
    final zoomedIn = _zoom > 1.05;
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
        (view.zoom - _zoom).abs() < 1e-6 &&
        (view.offset - offset).distance < 0.5;
    return same ? null : view;
  }

  /// The current view moved back inside the cell of [spread].
  ViewState _clampedToCell(int spread) {
    if (_zoom <= 1) return viewForSpread(spread, keepZoom: false);
    final cell = _layout!.spreadRect(spread);
    final visible = visibleRect;
    return (
      zoom: _zoom,
      offset: Offset(
        _ox.clamp(cell.left, cell.right - visible.width),
        _oy.clamp(cell.top, cell.bottom - visible.height),
      ),
    );
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
    page.value = currentPage;
  }

  void _clamp() {
    final layout = _layout;
    if (layout == null) return;
    final visible = visibleRect;
    final content = layout.contentSize;
    _ox = visible.width >= content.width
        ? -(visible.width - content.width) / 2
        : _ox.clamp(0, content.width - visible.width);
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
