// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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

/// State of the continuous reader (issue #47): layout, viewport, the image
/// cache and the render requests sent to the engine.
///
/// The view is `screen = (document - offset) * zoom`, in document units
/// (see [ContinuousLayout]). Pan and zoom only change numbers and bump
/// [repaint]; nothing is rebuilt (ADR-0006).
final class ReaderController {
  ReaderController({
    required this.engine,
    required this.document,
    required this.info,
    BitmapDecoder decoder = decodeBitmap,
    int cacheBudgetBytes = 160 << 20,
  }) : _decode = decoder,
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

  ContinuousLayout? _layout;
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

  ContinuousLayout? get layout => _layout;
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
  int get currentPage => _layout?.pageAt(visibleRect.center.dy) ?? 0;

  double get bucket => zoomBucket(_zoom);

  Offset toDocument(Offset screen) =>
      Offset(_ox + screen.dx / _zoom, _oy + screen.dy / _zoom);

  /// Lays the document out for a new view size, keeping the reading
  /// position.
  void resize(Size size, double devicePixelRatio) {
    if (size == _viewSize && devicePixelRatio == _devicePixelRatio) return;
    final widthChanged =
        size.width != _viewSize.width || devicePixelRatio != _devicePixelRatio;
    final old = _layout;
    ({int page, double fraction})? anchor;
    if (old != null && old.pageCount > 0) {
      final page = old.pageAt(_oy);
      final rect = old.pageRect(page);
      anchor = (page: page, fraction: (_oy - rect.top) / rect.height);
    }
    _viewSize = size;
    _devicePixelRatio = devicePixelRatio;
    if (size.width <= 0 || size.height <= 0) return;
    if (widthChanged || old == null) {
      _layout = ContinuousLayout(info, width: size.width);
      _layoutEpoch++;
      _pending.removeWhere((key, _) => key.startsWith('t:'));
      // Tile keys depend on the page width in pixels.
      cache.removeWhere((key) => key.startsWith('t:'));
      if (anchor != null) {
        final rect = _layout!.pageRect(anchor.page);
        _oy = rect.top + anchor.fraction * rect.height;
        _ox *= size.width / old!.width;
      }
    }
    _changed();
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

  /// Fit width: pages are as wide as the screen.
  void fitWidth() {
    final centre = _viewSize.center(Offset.zero);
    final point = toDocument(centre);
    _zoom = 1;
    _ox = 0;
    _oy = point.dy - centre.dy;
    _changed();
  }

  /// Fit page: the current page fits the screen, centred.
  void fitPage() {
    final layout = _layout;
    if (layout == null || layout.pageCount == 0) return;
    final rect = layout.pageRect(currentPage);
    _zoom = math
        .min(_viewSize.width / rect.width, _viewSize.height / rect.height)
        .clamp(minZoom, 1.0);
    _ox = rect.center.dx - _viewSize.width / _zoom / 2;
    _oy = rect.center.dy - _viewSize.height / _zoom / 2;
    _changed();
  }

  /// Double tap (FR-VIEW-004): zoom in on the tapped point, or back to fit
  /// width when already zoomed in.
  void smartZoom(Offset screenPoint) {
    if (_zoom > 1.05) {
      final point = toDocument(screenPoint);
      _zoom = 1;
      _ox = 0;
      _oy = point.dy - screenPoint.dy;
      _changed();
    } else {
      zoomAround(smartZoomLevel, toDocument(screenPoint), screenPoint);
    }
  }

  /// Shows [page] at the top of the screen.
  void goToPage(int page) {
    final layout = _layout;
    if (layout == null || page < 0 || page >= layout.pageCount) return;
    _oy = layout.pageRect(page).top;
    _changed();
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
      for (final page in layout.pagesIn(visible.top, visible.bottom)) ...[
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
  }

  void _clamp() {
    final layout = _layout;
    if (layout == null) return;
    final visible = visibleRect;
    _ox = visible.width >= layout.width
        ? -(visible.width - layout.width) / 2
        : _ox.clamp(0, layout.width - visible.width);
    _oy = visible.height >= layout.totalHeight
        ? -(visible.height - layout.totalHeight) / 2
        : _oy.clamp(0, layout.totalHeight - visible.height);
  }

  /// Asks the engine for what the screen needs, most urgent first: visible
  /// previews, visible tiles, then one screen ahead in both directions.
  void _ensure() {
    final layout = _layout;
    if (_disposed || layout == null || layout.pageCount == 0) return;
    _generation++;
    engine.setGeneration(document, _generation);
    final visible = visibleRect;
    final near = Rect.fromLTRB(
      visible.left,
      visible.top - visible.height,
      visible.right,
      visible.bottom + visible.height,
    );
    final visiblePages = layout.pagesIn(visible.top, visible.bottom).toList();
    for (final page in visiblePages) {
      _request(previewFor(layout, page), RenderPriority.visiblePreview);
    }
    for (final page in visiblePages) {
      for (final tile in _tiles(page, visible)) {
        _request(tile, RenderPriority.visibleTile);
      }
    }
    final nearPages = layout.pagesIn(near.top, near.bottom).toList();
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
  }
}
