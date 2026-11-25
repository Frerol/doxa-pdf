// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_pdf/features/reader/reader_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

DocumentInfo pages(int count, {double width = 400, double height = 600}) =>
    DocumentInfo(
      pageSizes: Float64List.fromList([
        for (var i = 0; i < count; i++) ...[width, height],
      ]),
      pageLabels: List.filled(count, null),
      metadata: const DocumentMetadata(),
    );

const view = Size(1000, 616); // 600 pt pages fit 600 px with 8 px margins.

StripLayout strip(
  int count,
  ReaderMode mode, {
  bool rightToLeft = false,
  bool coverPage = true,
}) => StripLayout(
  pages(count),
  options: ReaderOptions(
    mode: mode,
    rightToLeft: rightToLeft,
    coverPage: coverPage,
  ),
  viewSize: view,
);

void main() {
  group('single page (FR-VIEW-002)', () {
    final layout = strip(3, ReaderMode.singlePage);

    test('puts each page in its own screen-sized cell, centred', () {
      expect(layout.paged, isTrue);
      expect(layout.spreadCount, 3);
      expect(layout.spreadRect(1), const Rect.fromLTWH(1000, 0, 1000, 616));
      expect(layout.pageRect(1), const Rect.fromLTWH(1300, 8, 400, 600));
      expect(layout.contentSize, const Size(3000, 616));
    });

    test('finds pages and spreads by position', () {
      expect(layout.pageAt(const Offset(1500, 300)), 1);
      expect(layout.pageAt(const Offset(2999, 0)), 2);
      expect(layout.pagesIn(const Rect.fromLTWH(600, 0, 900, 616)), [0, 1]);
      expect(layout.pagesIn(const Rect.fromLTWH(1000, 0, 200, 616)), isEmpty);
      expect(layout.spreadBeside(1, towardsLeft: true), 0);
      expect(layout.spreadBeside(2, towardsLeft: false), isNull);
    });
  });

  group('two pages (FR-VIEW-003)', () {
    test('pairs pages after a cover on its own', () {
      final layout = strip(6, ReaderMode.twoPages);
      expect(
        [for (var s = 0; s < layout.spreadCount; s++) layout.pagesOf(s)],
        [
          [0],
          [1, 2],
          [3, 4],
          [5],
        ],
      );
      expect(layout.spreadOf(4), 2);
      // Two 400 × 600 pages side by side, 8 px apart, centred in the cell.
      expect(layout.pageRect(1), const Rect.fromLTWH(1096, 8, 400, 600));
      expect(layout.pageRect(2), const Rect.fromLTWH(1504, 8, 400, 600));
    });

    test('pairs from the first page without a cover', () {
      final layout = strip(4, ReaderMode.twoPages, coverPage: false);
      expect(layout.pagesOf(0), [0, 1]);
      expect(layout.pagesOf(1), [2, 3]);
    });

    test('shrinks spreads that are too wide for the screen', () {
      final layout = StripLayout(
        pages(2, width: 800, height: 600),
        options: const ReaderOptions(
          mode: ReaderMode.twoPages,
          coverPage: false,
        ),
        viewSize: view,
      );
      final page = layout.pageRect(0);
      expect(page.width * 2 + 8, closeTo(1000 - 16, 1e-9));
      expect(page.height, closeTo(page.width * 600 / 800, 1e-9));
    });
  });

  group('right to left (FR-VIEW-019)', () {
    test('reverses the cells and the pages of a spread', () {
      final layout = strip(5, ReaderMode.twoPages, rightToLeft: true);
      // Spreads [0] [1,2] [3,4]: the cover is the rightmost cell.
      expect(layout.spreadRect(0).left, 2000);
      expect(layout.spreadRect(2).left, 0);
      expect(layout.pageRect(2).left, lessThan(layout.pageRect(1).left));
      expect(layout.spreadBeside(0, towardsLeft: true), 1);
      expect(layout.spreadBeside(0, towardsLeft: false), isNull);
      expect(layout.pagesIn(const Rect.fromLTWH(0, 0, 3000, 616)), [
        0,
        1,
        2,
        3,
        4,
      ]);
    });
  });

  test('horizontal fits pages to the height, side by side', () {
    final layout = strip(3, ReaderMode.horizontal);
    expect(layout.paged, isFalse);
    expect(layout.pageRect(0).height, 600);
    expect(layout.pageRect(0).width, 400);
    expect(layout.spreadRect(1).left, layout.spreadRect(0).right);
    expect(layout.contentSize.width, layout.spreadRect(2).right);
  });

  test('buildLayout picks the layout of the mode', () {
    final info = pages(2);
    expect(
      buildLayout(info, const ReaderOptions(), view),
      isA<ContinuousLayout>(),
    );
    expect(
      buildLayout(info, const ReaderOptions(mode: ReaderMode.twoPages), view),
      isA<StripLayout>(),
    );
  });
}
