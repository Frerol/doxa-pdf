// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/testing.dart';
import 'package:doxa_pdf/features/reader/annotation_layer.dart';
import 'package:doxa_pdf/features/reader/reader_controller.dart';
import 'package:doxa_pdf/features/reader/reader_view.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'test_images.dart';

const _view = Size(400, 600);
final _shot = GlobalKey();

/// A page that shows 400 × 600 on screen with [rotation] and its crop box
/// at [origin], and where its quarters are in PDF user space.
({FakePage page, PdfRect topLeft, PdfRect bottomRight, PdfRect bottomLeft})
_page(int rotation, PdfPoint origin) {
  final page = FakePage(
    width: 400,
    height: 600,
    rotation: rotation,
    cropOrigin: origin,
  );
  final (x, y) = (origin.x, origin.y);
  // Turned by 90° clockwise, the user space's top-left quarter shows at
  // the top right, and its bottom-right quarter at the bottom left.
  return rotation == 0
      ? (
          page: page,
          topLeft: PdfRect(x, y + 300, x + 200, y + 600),
          bottomRight: PdfRect(x + 200, y, x + 400, y + 300),
          bottomLeft: PdfRect(x, y, x + 200, y + 300),
        )
      : (
          page: page,
          topLeft: PdfRect(x, y + 200, x + 300, y + 400),
          bottomRight: PdfRect(x + 300, y, x + 600, y + 200),
          bottomLeft: PdfRect(x, y, x + 300, y + 200),
        );
}

TextMarkup _highlight(PdfRect rect, {bool byDoxa = true}) => TextMarkup(
  id: byDoxa ? DoxaMarker.newId() : 'other-app',
  pageIndex: 0,
  kind: MarkupKind.highlight,
  quads: [PdfQuad.fromRect(rect)],
  byDoxa: byDoxa,
);

InkAnnotation _ink(PdfRect rect) => InkAnnotation(
  id: DoxaMarker.newId(),
  pageIndex: 0,
  strokes: [
    InkStroke([
      PdfPoint(rect.left + 20, (rect.bottom + rect.top) / 2),
      PdfPoint(rect.right - 20, (rect.bottom + rect.top) / 2),
    ]),
  ],
  width: 40,
  color: 0x000000,
  byDoxa: true,
);

Future<ReaderController> _show(
  WidgetTester tester,
  FakePage page, {
  List<Annotation> annotations = const [],
}) async {
  tester.view
    ..physicalSize = _view
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final engine = FakePdfEngine({
    'book.pdf': FakeDocument(
      pages: [
        FakePage(
          width: page.width,
          height: page.height,
          rotation: page.rotation,
          cropOrigin: page.cropOrigin,
          annotations: annotations,
        ),
      ],
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
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: _shot,
        child: ReaderView(controller: controller),
      ),
    ),
  );
  await _settle(tester);
  return controller;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// The screen's pixels, as RGBA.
Future<({int width, List<int> rgba})> _pixels(WidgetTester tester) async {
  final boundary =
      _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final data = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData();
    image.dispose();
    return bytes!.buffer.asUint8List();
  });
  return (width: _view.width.toInt(), rgba: data!);
}

/// The colour on screen at the middle of [rect] of page 0.
({int r, int g, int b}) _at(
  ReaderController controller,
  ({int width, List<int> rgba}) shot,
  PdfRect rect,
) {
  final document = controller.documentRect(0, rect)!.center;
  final screen = (document - controller.offset) * controller.zoom;
  final i = (screen.dy.round() * shot.width + screen.dx.round()) * 4;
  return (r: shot.rgba[i], g: shot.rgba[i + 1], b: shot.rgba[i + 2]);
}

bool _isPage(({int r, int g, int b}) c) =>
    (c.r - 128).abs() < 8 && (c.g - 128).abs() < 8 && (c.b - 128).abs() < 8;

void main() {
  group('Doxa annotations over the page (ADR-0005 §4)', () {
    for (final rotation in [0, 90]) {
      for (final origin in [const PdfPoint(0, 0), const PdfPoint(37.5, 62)]) {
        for (final zoom in [1.0, 2.0]) {
          testWidgets('markup and ink land on their place: rotation $rotation, '
              'crop box at (${origin.x}, ${origin.y}), zoom $zoom', (
            tester,
          ) async {
            final page = _page(rotation, origin);
            final controller = await _show(
              tester,
              page.page,
              annotations: [
                _highlight(page.topLeft),
                _ink(page.bottomRight),
                // Another app's markup is in the tiles, not drawn here.
                _highlight(page.bottomLeft, byDoxa: false),
              ],
            );
            if (zoom != 1) controller.zoomTo(zoom);

            // Yellow multiplied over the grey page: no blue left.
            await controller.reveal(0, page.topLeft);
            await _settle(tester);
            final markup = _at(controller, await _pixels(tester), page.topLeft);
            expect(markup.b, lessThan(40), reason: '$markup');
            expect(markup.r, greaterThan(100), reason: '$markup');

            await controller.reveal(0, page.bottomRight);
            await _settle(tester);
            final ink = _at(
              controller,
              await _pixels(tester),
              page.bottomRight,
            );
            expect(ink.r + ink.g + ink.b, lessThan(60), reason: '$ink');

            await controller.reveal(0, page.bottomLeft);
            await _settle(tester);
            final foreign = _at(
              controller,
              await _pixels(tester),
              page.bottomLeft,
            );
            expect(_isPage(foreign), isTrue, reason: '$foreign');
          });
        }
      }
    }

    testWidgets('committed ink is rasterised once, and again after a change', (
      tester,
    ) async {
      final page = _page(0, const PdfPoint(0, 0));
      final ink = _ink(page.bottomRight);
      final controller = await _show(tester, page.page, annotations: [ink]);
      final tile = controller
          .visibleTiles(0)
          .firstWhere((t) => controller.inkTile(t, InkTool.pen) != null);
      final first = controller.inkTile(tile, InkTool.pen);
      controller.repaint.value++;
      await tester.pump();
      expect(controller.inkTile(tile, InkTool.pen), same(first));

      controller.annotations.apply(
        UpdateAnnotation(before: ink, after: ink.copyWith(color: 0xFF0000)),
      );
      await tester.pump();
      final changed = controller.inkTile(tile, InkTool.pen);
      expect(changed, isNotNull);
      expect(changed, isNot(same(first)));
    });

    testWidgets('the live stroke shows on its layer and goes', (tester) async {
      final page = _page(0, const PdfPoint(0, 0));
      final controller = await _show(tester, page.page);
      final stroke = _ink(page.topLeft).strokes.single;
      controller.liveStroke.value = LiveStroke(
        pageIndex: 0,
        points: stroke.points,
        width: 40,
      );
      await tester.pump();
      final drawing = _at(controller, await _pixels(tester), page.topLeft);
      expect(drawing.r + drawing.g + drawing.b, lessThan(60));

      controller.liveStroke.value = null;
      await tester.pump();
      expect(
        _isPage(_at(controller, await _pixels(tester), page.topLeft)),
        isTrue,
      );
    });

    testWidgets('editing another app\'s annotation renders its page again', (
      tester,
    ) async {
      final engine = FakePdfEngine({
        'book.pdf': FakeDocument(
          pages: List.filled(3, const FakePage(width: 400, height: 600)),
        ),
      });
      tester.view
        ..physicalSize = _view
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened =
          await engine.open(const FileSource('book.pdf')) as DocumentOpened;
      final decoder = await FakeDecoder.create(tester);
      final controller = ReaderController(
        engine: engine,
        document: opened.handle,
        info: opened.info,
        decoder: decoder.call,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ReaderView(controller: controller)),
      );
      await _settle(tester);
      final before = engine.renderLog.length;
      controller.reloadPage(0);
      await _settle(tester);
      final again = engine.renderLog.skip(before).toList();
      expect(again, isNotEmpty);
      expect(again.map((r) => r.pageIndex).toSet(), {0});
    });
  });

  test('the user-to-document matrix maps like the page transform', () {
    final transform = PageTransform(
      cropBox: const PdfRect(37.5, 62, 637.5, 462),
      rotation: 270,
      scale: 0.5,
    );
    const pageRect = ui.Rect.fromLTWH(10, 20, 200, 300);
    final m = userToDocumentMatrix(transform, pageRect);
    for (final p in const [PdfPoint(37.5, 62), PdfPoint(300, 400)]) {
      final (vx, vy) = transform.toView(p);
      final x = m[0] * p.x + m[4] * p.y + m[12];
      final y = m[1] * p.x + m[5] * p.y + m[13];
      expect(x, closeTo(vx + pageRect.left, 1e-9));
      expect(y, closeTo(vy + pageRect.top, 1e-9));
    }
  });
}
