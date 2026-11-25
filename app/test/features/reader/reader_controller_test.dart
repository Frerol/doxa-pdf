// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/reader/reader_controller.dart';
import 'package:doxa_pdf/features/reader/reader_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_images.dart';

const viewSize = Size(400, 600);

Future<(ReaderController, FakePdfEngine, FakeDecoder)> openReader(
  WidgetTester tester, {
  int pages = 50,
  int cacheBudgetBytes = 160 << 20,
}) async {
  final engine = FakePdfEngine({
    'book.pdf': FakeDocument(
      pages: List.filled(pages, const FakePage(width: 400, height: 600)),
    ),
  });
  final opened =
      await engine.open(const FileSource('book.pdf')) as DocumentOpened;
  final decoder = await FakeDecoder.create(tester);
  final controller = ReaderController(
    engine: engine,
    document: opened.handle,
    info: opened.info,
    decoder: decoder.call,
    cacheBudgetBytes: cacheBudgetBytes,
  );
  addTearDown(controller.dispose);
  return (controller, engine, decoder);
}

/// Runs the fake engine's timers and the decoder until nothing is left.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// A widget test that lets pending renders finish before it ends.
void testReader(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      await body(tester);
      await settle(tester);
    });

void main() {
  testReader('requests visible previews first, then tiles, then nearby', (
    tester,
  ) async {
    final (controller, engine, _) = await openReader(tester);
    controller.resize(viewSize, 2);
    await settle(tester);

    final log = engine.renderLog;
    expect(log.first.priority, RenderPriority.visiblePreview);
    expect(log.first.pageIndex, 0);
    final priorities = log.map((r) => r.priority).toList();
    expect(
      priorities.indexOf(RenderPriority.visibleTile),
      greaterThan(priorities.lastIndexOf(RenderPriority.visiblePreview)),
    );
    expect(priorities, contains(RenderPriority.nearPreview));
    // The screen shows page 0 only (600 px high pages, 8 px gap).
    expect(
      log
          .where((r) => r.priority == RenderPriority.visibleTile)
          .map((r) => r.pageIndex),
      everyElement(0),
    );
    expect(controller.cache.contains('p:0'), isTrue);
    expect(controller.pendingRequests, 0);
  });

  testReader('does not request what it already has', (tester) async {
    final (controller, engine, _) = await openReader(tester);
    controller.resize(viewSize, 1);
    await settle(tester);
    final first = engine.renderLog.length;
    controller.panBy(Offset.zero);
    await settle(tester);
    expect(engine.renderLog.length, first);
  });

  testReader('asks again for stale tiles that are still on screen', (
    tester,
  ) async {
    final (controller, engine, _) = await openReader(tester);
    controller.resize(viewSize, 1);
    // Several viewport generations before any render completes.
    controller
      ..panBy(const Offset(0, -10))
      ..panBy(const Offset(0, -10))
      ..panBy(const Offset(0, -10));
    await settle(tester);
    for (final key in controller.visibleKeys()) {
      expect(controller.cache.contains(key), isTrue, reason: key);
    }
  });

  testReader('clamps the view to the document', (tester) async {
    final (controller, _, _) = await openReader(tester, pages: 3);
    controller.resize(viewSize, 1);
    controller.panBy(const Offset(100, 100));
    expect(controller.offset, Offset.zero);
    controller.panBy(const Offset(0, -1e6));
    final layout = controller.layout!;
    expect(controller.offset.dy, layout.totalHeight - viewSize.height);
    // Zoomed out, the pages are centred horizontally.
    controller.zoomTo(0.5);
    expect(controller.offset.dx, -200);
  });

  testReader('zooms around the focal point and limits the zoom', (
    tester,
  ) async {
    final (controller, _, _) = await openReader(tester);
    controller.resize(viewSize, 1);
    const focal = Offset(100, 300);
    final before = controller.toDocument(focal);
    controller.zoomAround(2, before, focal);
    expect(controller.zoom, 2);
    expect(controller.toDocument(focal), before);
    controller.zoomAround(100, before, focal);
    expect(controller.zoom, ReaderController.maxZoom);
    controller.zoomAround(0, before, focal);
    expect(controller.zoom, ReaderController.minZoom);
  });

  testReader('fit width, fit page and smart zoom (FR-VIEW-004)', (
    tester,
  ) async {
    final (controller, _, _) = await openReader(tester);
    controller.resize(viewSize, 1);
    controller.goToPage(10);
    controller.fitPage();
    expect(controller.zoom, 1); // A 400 × 600 page fits exactly.
    controller.resize(const Size(400, 300), 1);
    controller.fitPage();
    expect(controller.zoom, 0.5);
    expect(controller.currentPage, 10);
    final page = controller.layout!.pageRect(10);
    expect(controller.visibleRect.center.dy, closeTo(page.center.dy, 1e-6));

    controller.fitWidth();
    expect(controller.zoom, 1);
    expect(controller.offset.dx, 0);

    controller.smartZoom(const Offset(100, 100));
    expect(controller.zoom, ReaderController.smartZoomLevel);
    controller.smartZoom(const Offset(100, 100));
    expect(controller.zoom, 1);
  });

  testReader('keeps the reading position when the width changes', (
    tester,
  ) async {
    final (controller, _, _) = await openReader(tester);
    controller.resize(viewSize, 1);
    controller.goToPage(20);
    controller.panBy(const Offset(0, -150)); // A quarter into page 20.
    controller.resize(const Size(800, 500), 1);
    final page = controller.layout!.pageRect(20);
    expect(controller.offset.dy, closeTo(page.top + page.height / 4, 1e-6));
  });

  testReader('evicts old images over budget, never visible ones', (
    tester,
  ) async {
    // Each fake image is 4 × 4 px = 64 bytes.
    final (controller, _, _) = await openReader(tester, cacheBudgetBytes: 640);
    controller.resize(viewSize, 1);
    await settle(tester);
    for (var page = 1; page < 30; page += 2) {
      controller.goToPage(page);
      await settle(tester);
    }
    expect(controller.cache.bytes, lessThanOrEqualTo(640));
    for (final key in controller.visibleKeys()) {
      expect(controller.cache.contains(key), isTrue, reason: key);
    }
    expect(controller.cache.contains('p:0'), isFalse);
  });

  testReader('trimMemory keeps only what is on screen', (tester) async {
    final (controller, _, _) = await openReader(tester);
    controller.resize(viewSize, 1);
    await settle(tester);
    expect(
      controller.cache.length,
      greaterThan(controller.visibleKeys().length),
    );
    controller.trimMemory();
    expect(controller.cache.keys.toSet(), controller.visibleKeys());
  });

  testReader('drops tiles rendered for an older layout', (tester) async {
    final (controller, _, decoder) = await openReader(tester);
    final gate = Completer<void>();
    final widthOf = <ui.Image, int>{};
    final gated = ReaderController(
      engine: controller.engine,
      document: controller.document,
      info: controller.info,
      decoder: (bitmap) async {
        // Hold back the tiles of the first layout (400 px wide pages).
        if (bitmap.width == 400) await gate.future;
        final image = await decoder(bitmap);
        widthOf[image] = bitmap.width;
        return image;
      },
    );
    addTearDown(gated.dispose);
    gated.resize(viewSize, 1);
    // Renders finish; old tiles wait at the gate.
    await tester.pump(const Duration(milliseconds: 1));
    gated.resize(const Size(600, 400), 1); // The tablet rotates.
    await settle(tester); // New tiles arrive first...
    gate.complete(); // ...then the old ones.
    await settle(tester);

    final tiles = gated.cache.keys.where((k) => k.startsWith('t:')).toList();
    expect(tiles, isNotEmpty);
    for (final key in tiles) {
      final page = int.parse(key.split(':')[1]);
      final spec = tilesFor(
        gated.layout!,
        page,
        bucket: gated.bucket,
        devicePixelRatio: 1,
        visible: gated.layout!.pageRect(page),
      ).singleWhere((t) => t.key == key);
      expect(widthOf[gated.cache.peek(key)], spec.width, reason: key);
    }
  });

  testReader('a disposed controller drops late renders', (tester) async {
    final engine = FakePdfEngine({
      'book.pdf': const FakeDocument(pages: [FakePage()]),
    }, renderDelay: const Duration(milliseconds: 5));
    final opened =
        await engine.open(const FileSource('book.pdf')) as DocumentOpened;
    final decoder = await FakeDecoder.create(tester);
    final controller = ReaderController(
      engine: engine,
      document: opened.handle,
      info: opened.info,
      decoder: decoder.call,
    )..resize(viewSize, 1);
    controller.dispose();
    await settle(tester);
    expect(decoder.decoded, isEmpty);
  });
}
