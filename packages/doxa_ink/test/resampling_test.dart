// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_ink/doxa_ink.dart';
import 'package:test/test.dart';

void main() {
  final line = [
    for (var i = 0; i < 6; i++) InkSample(i.toDouble(), 0, i / 5, i * 10),
  ];
  test('distance resampling counts and endpoint identity', () {
    expect(resampleByDistance(line, 2), [line[0], line[2], line[4], line[5]]);
    expect(resampleByDistance(line, 99), [line.first, line.last]);
    expect(resampleByDistance(line, 0), line);
  });
  test('distance is measured from last kept sample in two dimensions', () {
    const points = [
      InkSample(0, 0, 0, 0),
      InkSample(0, 1, 0, 1),
      InkSample(0, 2, 0, 2),
      InkSample(0, 3, 0, 3),
    ];
    expect(resampleByDistance(points, 2), [points[0], points[2], points[3]]);
  });
  test('empty and short inputs are copied', () {
    for (final points in [
      <InkSample>[],
      line.take(1).toList(),
      line.take(2).toList(),
    ]) {
      expect(resampleByDistance(points, 5), points);
      expect(simplify(points, 5), points);
      expect(identical(simplify(points, 5), points), isFalse);
    }
  });
  test('collinear samples collapse and zero tolerance keeps everything', () {
    expect(simplify(line, 0.01), [line.first, line.last]);
    expect(simplify(line, 0), line);
  });
  test('RDP keeps corners with original pressure and timestamp', () {
    const points = [
      InkSample(0, 0, 0.1, 1),
      InkSample(1, 2, 0.9, 2),
      InkSample(2, 0, 0.3, 3),
    ];
    expect(simplify(points, 1), points);
    expect(simplify(points, 2), [points.first, points.last]);
  });
  test('closed and duplicate positions remain well defined', () {
    final points = [line.first, line[2], line.first];
    expect(simplify(points, 1), points);
    expect(simplify([line.first, line.first, line.first], 1).length, 2);
  });
}
