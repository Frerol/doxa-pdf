// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui';

import 'package:doxa_engine/doxa_engine.dart';

/// Physical size of a render tile (ADR-0005).
const tilePixels = 512;

/// Physical width of the low-resolution page previews (ADR-0005).
const previewPixels = 360;

/// How pages are arranged (FR-VIEW-002, FR-VIEW-003).
enum ReaderMode { continuous, singlePage, twoPages, horizontal }

/// Layout and page-turning options of the reader.
final class ReaderOptions {
  const ReaderOptions({
    this.mode = ReaderMode.continuous,
    this.coverPage = true,
    this.rightToLeft = false,
    this.tapZones = true,
    this.keepZoomOnTurn = false,
  });

  final ReaderMode mode;

  /// In two-page mode, the first page stands alone (FR-VIEW-003).
  final bool coverPage;

  /// Pages progress from right to left (FR-VIEW-019).
  final bool rightToLeft;

  /// Tapping near the left or right edge turns the page (FR-VIEW-017).
  final bool tapZones;

  /// Turning a page keeps the zoom and the horizontal offset (FR-VIEW-018).
  final bool keepZoomOnTurn;

  /// One spread per screen, turned like a book.
  bool get paged =>
      mode == ReaderMode.singlePage || mode == ReaderMode.twoPages;

  ReaderOptions copyWith({
    ReaderMode? mode,
    bool? coverPage,
    bool? rightToLeft,
    bool? tapZones,
    bool? keepZoomOnTurn,
  }) => ReaderOptions(
    mode: mode ?? this.mode,
    coverPage: coverPage ?? this.coverPage,
    rightToLeft: rightToLeft ?? this.rightToLeft,
    tapZones: tapZones ?? this.tapZones,
    keepZoomOnTurn: keepZoomOnTurn ?? this.keepZoomOnTurn,
  );

  @override
  bool operator ==(Object other) =>
      other is ReaderOptions &&
      mode == other.mode &&
      coverPage == other.coverPage &&
      rightToLeft == other.rightToLeft &&
      tapZones == other.tapZones &&
      keepZoomOnTurn == other.keepZoomOnTurn;

  @override
  int get hashCode =>
      Object.hash(mode, coverPage, rightToLeft, tapZones, keepZoomOnTurn);
}

/// Where every page sits, in document units: logical pixels at zoom 1.
///
/// A *spread* is what one screen shows in paged modes: one page, or two
/// side by side. In the other modes every page is its own spread.
abstract interface class PageLayout {
  DocumentInfo get info;
  int get pageCount;
  Size get contentSize;

  /// One spread per screen; the view settles on a spread after a gesture.
  bool get paged;

  /// Whether the layout depends on the view height (not only its width).
  bool get usesViewHeight;

  Rect pageRect(int page);

  /// Pages that intersect [area], in page order.
  Iterable<int> pagesIn(Rect area);

  /// The page at [point], or the nearest one.
  int pageAt(Offset point);

  int get spreadCount;
  int spreadOf(int page);
  List<int> pagesOf(int spread);

  /// The screen-sized cell of [spread] in paged layouts, otherwise the
  /// bounds of its pages.
  Rect spreadRect(int spread);

  /// The spread next to [spread] on the screen, or null at the end.
  int? spreadBeside(int spread, {required bool towardsLeft});
}

/// Builds the layout of [options] for a view of [viewSize].
PageLayout buildLayout(
  DocumentInfo info,
  ReaderOptions options,
  Size viewSize,
) => switch (options.mode) {
  ReaderMode.continuous => ContinuousLayout(info, width: viewSize.width),
  _ => StripLayout(info, options: options, viewSize: viewSize),
};

({double width, double height}) _sizeOf(DocumentInfo info, int page) {
  final size = info.pageSize(page);
  return size.width > 0 && size.height > 0
      ? size
      : (width: 612.0, height: 792.0);
}

/// Continuous vertical layout (FR-VIEW-002): every page is as wide as the
/// viewport, one below the other.
final class ContinuousLayout implements PageLayout {
  ContinuousLayout(this.info, {required this.width, this.gap = 8})
    : assert(width > 0) {
    var y = 0.0;
    for (var i = 0; i < info.pageCount; i++) {
      final size = _sizeOf(info, i);
      final height = size.height * width / size.width;
      _tops.add(y);
      _heights.add(height);
      y += height + gap;
    }
    totalHeight = info.pageCount == 0 ? 0 : y - gap;
  }

  @override
  final DocumentInfo info;
  final double width;
  final double gap;
  final _tops = <double>[];
  final _heights = <double>[];
  late final double totalHeight;

  @override
  int get pageCount => _tops.length;
  @override
  Size get contentSize => Size(width, totalHeight);
  @override
  bool get paged => false;
  @override
  bool get usesViewHeight => false;

  @override
  Rect pageRect(int page) =>
      Rect.fromLTWH(0, _tops[page], width, _heights[page]);

  @override
  int pageAt(Offset point) => pageAtY(point.dy);

  /// The page that contains [y], or the nearest one above.
  int pageAtY(double y) {
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

  @override
  Iterable<int> pagesIn(Rect area) sync* {
    if (pageCount == 0 || area.bottom < 0 || area.top > totalHeight) return;
    if (area.right < 0 || area.left > width) return;
    for (var i = pageAtY(math.max(0, area.top)); i < pageCount; i++) {
      if (_tops[i] > area.bottom) break;
      if (_tops[i] + _heights[i] >= area.top) yield i;
    }
  }

  @override
  int get spreadCount => pageCount;
  @override
  int spreadOf(int page) => page;
  @override
  List<int> pagesOf(int spread) => [spread];
  @override
  Rect spreadRect(int spread) => pageRect(spread);
  @override
  int? spreadBeside(int spread, {required bool towardsLeft}) => null;
}

/// Pages in a horizontal strip (FR-VIEW-002, FR-VIEW-003, FR-VIEW-019).
///
/// - Single page and two pages: one screen-sized cell per spread, with the
///   spread fitted inside it. A two-page spread puts its first page on the
///   left, or on the right when reading right to left.
/// - Horizontal: pages fitted to the view height, side by side.
///
/// Right to left reverses the order of the cells on the screen.
final class StripLayout implements PageLayout {
  StripLayout(this.info, {required this.options, required Size viewSize})
    : assert(viewSize.width > 0 && viewSize.height > 0) {
    final count = info.pageCount;
    _pageRects = List.filled(count, Rect.zero);
    _spreadOfPage = List.filled(count, 0);
    final spreads = <List<int>>[];
    if (options.mode == ReaderMode.twoPages) {
      var page = 0;
      if (options.coverPage && count > 0) spreads.add([page++]);
      while (page < count) {
        spreads.add([page, if (page + 1 < count) page + 1]);
        page += 2;
      }
    } else {
      for (var page = 0; page < count; page++) {
        spreads.add([page]);
      }
    }
    _spreads = spreads;
    final order = List.generate(spreads.length, (i) => i);
    final visual = options.rightToLeft ? order.reversed.toList() : order;
    var x = 0.0;
    _cells = List.filled(spreads.length, Rect.zero);
    for (final spread in visual) {
      final pages = spreads[spread];
      final cell = _layOut(pages, x, viewSize);
      _cells[spread] = cell;
      _visualOrder.add(spread);
      _visualLefts.add(cell.left);
      x = cell.right;
      for (final page in pages) {
        _spreadOfPage[page] = spread;
      }
    }
    contentSize = Size(x, viewSize.height);
  }

  /// Space around a spread inside its cell, and between pages.
  static const margin = 8.0;

  @override
  final DocumentInfo info;
  final ReaderOptions options;
  late final List<Rect> _pageRects;
  late final List<int> _spreadOfPage;
  late final List<List<int>> _spreads;
  late final List<Rect> _cells;
  final _visualOrder = <int>[];
  final _visualLefts = <double>[];

  @override
  late final Size contentSize;

  /// Places [pages] in a cell that starts at [left] and returns the cell.
  Rect _layOut(List<int> pages, double left, Size view) {
    final aspects = [
      for (final page in pages)
        _sizeOf(info, page).width / _sizeOf(info, page).height,
    ];
    final aspectSum = aspects.fold<double>(0, (a, b) => a + b);
    final gaps = margin * (pages.length - 1);
    final innerHeight = math.max(1.0, view.height - 2 * margin);
    final innerWidth = math.max(1.0, view.width - 2 * margin);
    final double height;
    final double cellWidth;
    if (paged) {
      height = math.max(
        1.0,
        math.min(innerHeight, (innerWidth - gaps) / aspectSum),
      );
      cellWidth = view.width;
    } else {
      height = innerHeight;
      cellWidth = height * aspectSum + gaps + margin;
    }
    final spreadWidth = height * aspectSum + gaps;
    var x = left + (cellWidth - spreadWidth) / 2;
    final y = (view.height - height) / 2;
    // The first page of a spread sits on the reading side.
    final ordered = options.rightToLeft ? pages.reversed : pages;
    for (final page in ordered) {
      final width = height * aspects[pages.indexOf(page)];
      _pageRects[page] = Rect.fromLTWH(x, y, width, height);
      x += width + margin;
    }
    return Rect.fromLTWH(left, 0, cellWidth, view.height);
  }

  @override
  int get pageCount => _pageRects.length;
  @override
  bool get paged => options.paged;
  @override
  bool get usesViewHeight => true;
  @override
  Rect pageRect(int page) => _pageRects[page];
  @override
  int get spreadCount => _spreads.length;
  @override
  int spreadOf(int page) => _spreadOfPage[page];
  @override
  List<int> pagesOf(int spread) => _spreads[spread];
  @override
  Rect spreadRect(int spread) => _cells[spread];

  /// Index in [_visualOrder] of the cell at [x], or the nearest one.
  int _visualIndexAt(double x) {
    if (_visualLefts.isEmpty) return 0;
    var lo = 0, hi = _visualLefts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_visualLefts[mid] <= x) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The spread whose cell contains [point], or the nearest one.
  int spreadAt(Offset point) =>
      _visualOrder.isEmpty ? 0 : _visualOrder[_visualIndexAt(point.dx)];

  @override
  int pageAt(Offset point) {
    if (pageCount == 0) return 0;
    final pages = pagesOf(spreadAt(point));
    var best = pages.first;
    var bestDistance = double.infinity;
    for (final page in pages) {
      final rect = pageRect(page);
      final distance = point.dx < rect.left
          ? rect.left - point.dx
          : point.dx > rect.right
          ? point.dx - rect.right
          : 0.0;
      if (distance < bestDistance) {
        best = page;
        bestDistance = distance;
      }
    }
    return best;
  }

  @override
  Iterable<int> pagesIn(Rect area) {
    if (pageCount == 0) return const [];
    final pages = <int>[];
    for (var i = _visualIndexAt(area.left); i < _visualOrder.length; i++) {
      final cell = _cells[_visualOrder[i]];
      if (cell.left > area.right) break;
      for (final page in pagesOf(_visualOrder[i])) {
        if (pageRect(page).overlaps(area)) pages.add(page);
      }
    }
    return pages..sort();
  }

  @override
  int? spreadBeside(int spread, {required bool towardsLeft}) {
    final index = _visualOrder.indexOf(spread) + (towardsLeft ? -1 : 1);
    return index < 0 || index >= _visualOrder.length
        ? null
        : _visualOrder[index];
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
TileSpec previewFor(PageLayout layout, int page) {
  final scale = previewPixels / _sizeOf(layout.info, page).width;
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
  PageLayout layout,
  int page, {
  required double bucket,
  required double devicePixelRatio,
  required Rect visible,
}) sync* {
  final rect = layout.pageRect(page);
  final area = rect.intersect(visible);
  if (area.isEmpty) return;
  final widthPt = _sizeOf(layout.info, page).width;
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
