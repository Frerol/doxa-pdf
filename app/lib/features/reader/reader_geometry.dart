// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui';

import 'package:doxa_engine/doxa_engine.dart';

/// Physical size of a render tile (ADR-0005).
const tilePixels = 512;

/// Physical width of the low-resolution page previews (ADR-0005).
const previewPixels = 360;

/// Continuous vertical layout (FR-VIEW-002) in document units: logical
/// pixels at zoom 1, where every page is as wide as the viewport.
final class ContinuousLayout {
  ContinuousLayout(this.info, {required this.width, this.gap = 8})
    : assert(width > 0) {
    var y = 0.0;
    for (var i = 0; i < info.pageCount; i++) {
      final size = info.pageSize(i);
      final height = size.width > 0 && size.height > 0
          ? size.height * width / size.width
          : width * 11 / 8.5;
      _tops.add(y);
      _heights.add(height);
      y += height + gap;
    }
    totalHeight = info.pageCount == 0 ? 0 : y - gap;
  }

  final DocumentInfo info;
  final double width;
  final double gap;
  final _tops = <double>[];
  final _heights = <double>[];
  late final double totalHeight;

  int get pageCount => _tops.length;

  Rect pageRect(int page) =>
      Rect.fromLTWH(0, _tops[page], width, _heights[page]);

  /// The page that contains [y], or the nearest one.
  int pageAt(double y) {
    if (pageCount == 0) return 0;
    var lo = 0, hi = pageCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_tops[mid] <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Pages that intersect `[top, bottom]`, in order.
  Iterable<int> pagesIn(double top, double bottom) sync* {
    if (pageCount == 0 || bottom < 0 || top > totalHeight) return;
    for (var i = pageAt(math.max(0, top)); i < pageCount; i++) {
      if (_tops[i] > bottom) break;
      if (_tops[i] + _heights[i] >= top) yield i;
    }
  }
}

/// Power-of-two zoom bucket used for tiles, so a pinch reuses tiles until
/// the zoom crosses the next power of two (ADR-0005).
double zoomBucket(double zoom) {
  final exponent = (math.log(zoom) / math.ln2 - 1e-9).ceil();
  return math.pow(2, exponent.clamp(-2, 4)).toDouble();
}

/// One render request and where its image goes, in document units.
final class TileSpec {
  const TileSpec({
    required this.key,
    required this.page,
    required this.scale,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.destination,
  });

  final String key;
  final int page;

  /// Pixels per point.
  final double scale;
  final int x;
  final int y;
  final int width;
  final int height;
  final Rect destination;

  RenderRequest request(
    DocumentHandle document, {
    required RenderPriority priority,
    required int generation,
  }) => RenderRequest(
    document: document,
    pageIndex: page,
    scale: scale,
    x: x,
    y: y,
    width: width,
    height: height,
    priority: priority,
    generation: generation,
  );
}

/// The preview of [page]: [previewPixels] wide, covering the whole page.
TileSpec previewFor(ContinuousLayout layout, int page) {
  final size = layout.info.pageSize(page);
  final widthPt = size.width > 0 ? size.width : 612.0;
  final scale = previewPixels / widthPt;
  final rect = layout.pageRect(page);
  return TileSpec(
    key: 'p:$page',
    page: page,
    scale: scale,
    x: 0,
    y: 0,
    width: previewPixels,
    height: math.max(1, (rect.height / rect.width * previewPixels).ceil()),
    destination: rect,
  );
}

/// Tiles of [page] at [bucket] that intersect [visible] (document units),
/// for a screen with [devicePixelRatio].
Iterable<TileSpec> tilesFor(
  ContinuousLayout layout,
  int page, {
  required double bucket,
  required double devicePixelRatio,
  required Rect visible,
}) sync* {
  final rect = layout.pageRect(page);
  final area = rect.intersect(visible);
  if (area.isEmpty) return;
  final size = layout.info.pageSize(page);
  final widthPt = size.width > 0 ? size.width : 612.0;
  // Physical pixels per document unit, and per point.
  final pxPerUnit = bucket * devicePixelRatio;
  final scale = rect.width / widthPt * pxPerUnit;
  final pageWidthPx = (rect.width * pxPerUnit).ceil();
  final pageHeightPx = (rect.height * pxPerUnit).ceil();
  final tileUnits = tilePixels / pxPerUnit;
  final firstColumn = ((area.left - rect.left) / tileUnits).floor();
  final lastColumn = ((area.right - rect.left) / tileUnits).ceil();
  final firstRow = ((area.top - rect.top) / tileUnits).floor();
  final lastRow = ((area.bottom - rect.top) / tileUnits).ceil();
  for (var row = math.max(0, firstRow); row < lastRow; row++) {
    final y = row * tilePixels;
    if (y >= pageHeightPx) break;
    for (var column = math.max(0, firstColumn); column < lastColumn; column++) {
      final x = column * tilePixels;
      if (x >= pageWidthPx) break;
      final width = math.min(tilePixels, pageWidthPx - x);
      final height = math.min(tilePixels, pageHeightPx - y);
      yield TileSpec(
        key: 't:$page:$bucket:$column:$row',
        page: page,
        scale: scale,
        x: x,
        y: y,
        width: width,
        height: height,
        destination: Rect.fromLTWH(
          rect.left + x / pxPerUnit,
          rect.top + y / pxPerUnit,
          width / pxPerUnit,
          height / pxPerUnit,
        ),
      );
    }
  }
}
