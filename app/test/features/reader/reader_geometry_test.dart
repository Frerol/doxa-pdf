// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_pdf/features/reader/reader_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

DocumentInfo infoOf(List<(double, double)> sizes) => DocumentInfo(
  pageSizes: Float64List.fromList([
    for (final (w, h) in sizes) ...[w, h],
  ]),
  pageLabels: List.filled(sizes.length, null),
  metadata: const DocumentMetadata(),
);

void main() {
  group('ContinuousLayout', () {
    final layout = ContinuousLayout(
      infoOf([(612, 792), (792, 612), (300, 300)]),
      width: 600,
      gap: 10,
    );

    test('scales every page to the view width', () {
      expect(
        layout.pageRect(0),
        const Rect.fromLTWH(0, 0, 600, 600 * 792 / 612),
      );
      expect(layout.pageRect(1).top, closeTo(776.47 + 10, 0.01));
      expect(layout.pageRect(1).height, closeTo(600 * 612 / 792, 1e-9));
      expect(layout.pageRect(2).height, 600);
      expect(layout.totalHeight, closeTo(layout.pageRect(2).bottom, 1e-9));
    });

    test('finds pages by position', () {
      expect(layout.pageAtY(-50), 0);
      expect(layout.pageAtY(0), 0);
      expect(layout.pageAtY(780), 0); // In the gap after page 0.
      expect(layout.pageAtY(790), 1);
      expect(layout.pageAtY(1e9), 2);
      expect(layout.pagesIn(const Rect.fromLTRB(0, 700, 600, 800)).toList(), [
        0,
        1,
      ]);
      expect(
        layout.pagesIn(const Rect.fromLTRB(0, 778, 600, 784)).toList(),
        isEmpty,
      );
      expect(layout.pagesIn(const Rect.fromLTRB(0, -100, 600, 1e9)).toList(), [
        0,
        1,
        2,
      ]);
    });

    test('lays out a thousand pages quickly', () {
      final big = ContinuousLayout(
        infoOf(List.filled(5000, (612.0, 792.0))),
        width: 800,
      );
      final watch = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        big.pagesIn(Rect.fromLTWH(0, i * 100.0, 800, 1200)).length;
      }
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(big.pageAtY(big.pageRect(4321).top + 1), 4321);
    });
  });

  test('zoomBucket rounds up to a power of two', () {
    expect(zoomBucket(1), 1);
    expect(zoomBucket(1.01), 2);
    expect(zoomBucket(2), 2);
    expect(zoomBucket(3), 4);
    expect(zoomBucket(0.6), 1);
    expect(zoomBucket(0.4), 0.5);
    expect(zoomBucket(0.01), 0.25);
    expect(zoomBucket(100), 16);
  });

  group('tiles', () {
    final layout = ContinuousLayout(infoOf([(600, 800)]), width: 300, gap: 0);

    test('cover the visible part of the page without overlap', () {
      // dpr 2, bucket 2: 4 px per unit, page 1200 × 1600 px.
      final tiles = tilesFor(
        layout,
        0,
        bucket: 2,
        devicePixelRatio: 2,
        visible: const Rect.fromLTWH(0, 0, 300, 400),
      ).toList();
      expect(tiles, hasLength(3 * 4));
      expect(tiles.first.scale, 2); // 1200 px / 600 pt.
      final last = tiles.last;
      expect((last.x, last.y, last.width, last.height), (1024, 1536, 176, 64));
      final area = tiles.fold<double>(
        0,
        (sum, t) => sum + t.destination.width * t.destination.height,
      );
      expect(area, closeTo(300 * 400, 1e-6));
      expect(tiles.map((t) => t.key).toSet(), hasLength(tiles.length));
    });

    test('include only tiles that intersect the visible rect', () {
      final tiles = tilesFor(
        layout,
        0,
        bucket: 1,
        devicePixelRatio: 2,
        visible: const Rect.fromLTWH(10, 300, 20, 20),
      ).toList();
      // 2 px per unit: the rect is px (20,600)–(60,640), in tile row 1.
      expect(tiles.single.key, 't:0:1.0:0:1');
      expect(tiles.single.destination.contains(const Offset(20, 310)), isTrue);
    });

    test('previews are 360 px wide and cover the page', () {
      final preview = previewFor(layout, 0);
      expect(preview.width, previewPixels);
      expect(preview.height, 480);
      expect(preview.scale, previewPixels / 600);
      expect(preview.destination, layout.pageRect(0));
    });
  });
}
