// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_android/engine.dart';

void main() {
  test('300 dpi raster, full save and searchable aligned word', () async {
    final work = Directory.current.createTempSync('.ocr-test-');
    addTearDown(() => work.deleteSync(recursive: true));
    final engine = await Engine.start();
    addTearDown(() => engine.call<void>('shutdown'));
    final source = File('../../test_corpus/scanned-300.pdf').absolute.path;
    final output = '${work.path}/copy.pdf';
    expect(await engine.call<int>('open', [source]), 1);
    final raster = await engine.call<Raster>('raster', [0]);
    expect((raster.width, raster.height), (2550, 3300));
    final pixels = raster.data.materialize().asUint8List();
    expect(pixels.length, raster.width * raster.height);
    expect(pixels.any((pixel) => pixel < 128), isTrue);
    expect(pixels.any((pixel) => pixel == 255), isTrue);

    await engine.call<void>('begin', [source]);
    expect(
      await engine.call<int>('write', [
        0,
        raster.width,
        raster.height,
        [
          {
            'text': 'ação',
            'left': 255,
            'top': 330,
            'right': 510,
            'bottom': 363,
          },
        ],
      ]),
      1,
    );
    await engine.call<Object>('save', [output]);
    expect(await engine.call<List<SearchHit>>('search', [source, 'ação']), []);
    final hits = await engine.call<List<SearchHit>>('search', [output, 'ação']);
    expect(hits.single.page, 0);
    final box = hits.single.rectangles.single;
    expect(box.left, closeTo(1000, 1));
    expect(box.top, closeTo(1000, 1));
    expect(box.right, closeTo(2000, 1));
    expect(box.bottom, closeTo(1100, 1));
  });
}
