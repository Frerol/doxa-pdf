// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:doxa_engine/doxa_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Creates a real image; call inside `tester.runAsync`.
Future<ui.Image> solidImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF808080),
  );
  return recorder.endRecording().toImage(width, height);
}

/// A decoder that skips the real (asynchronous) pixel decoding: it hands
/// out clones of one prepared image, sized like the bitmap.
final class FakeDecoder {
  FakeDecoder(this._base);

  static Future<FakeDecoder> create(WidgetTester tester) async {
    final base = await tester.runAsync(() => solidImage(4, 4));
    return FakeDecoder(base!);
  }

  final ui.Image _base;
  final decoded = <(int, int)>[];

  Future<ui.Image> call(RenderedBitmap bitmap) async {
    decoded.add((bitmap.width, bitmap.height));
    return _base.clone();
  }
}
