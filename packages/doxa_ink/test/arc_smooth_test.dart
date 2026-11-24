// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_ink/doxa_ink.dart';
import 'package:test/test.dart';

void main() {
  const line = [
    InkSample(0, 0, 0, 0),
    InkSample(4, 4, 0.5, 10),
    InkSample(8, 8, 1, 20),
  ];
  test('identity cases return a copy', () {
    for (final raw in [
      <InkSample>[],
      line.take(1).toList(),
      line.take(2).toList(),
      line,
    ]) {
      for (final radius in [0.0, -1.0]) {
        final result = arcSmooth(raw, radius);
        expect(result, raw);
        expect(identical(result, raw), isFalse);
      }
    }
    expect(arcSmooth(line.take(2).toList(), 4), line.take(2));
  });
  test('preserves endpoints and straight line with pressure', () {
    final result = arcSmooth(line, 4);
    expect(
      [
        result.first.x,
        result.first.y,
        result.first.pressure,
        result.first.timeUs,
      ],
      [0, 0, 0, 0],
    );
    expect(
      [result.last.x, result.last.y, result.last.pressure, result.last.timeUs],
      [8, 8, 1, 20],
    );
    for (final p in result) {
      expect(p.y, closeTo(p.x, 1e-12));
      expect(p.pressure, closeTo(p.x / 8, 1e-12));
    }
  });
  test('reduces zigzag amplitude', () {
    final raw = [
      for (var i = 0; i < 30; i++)
        InkSample(i.toDouble(), i.isEven ? -1 : 1, 0.5, i),
    ];
    final result = arcSmooth(raw, 8);
    expect(
      result.skip(5).take(result.length - 10).every((p) => p.y.abs() < 0.6),
      isTrue,
    );
  });
  test('duplicate positions produce finite output', () {
    final result = arcSmooth([line.first, line.first, line.last, line.last], 4);
    expect(
      result.every((p) => p.x.isFinite && p.y.isFinite && p.pressure.isFinite),
      isTrue,
    );
    expect(arcSmooth([line.first, line.first, line.first], 4).length, 2);
  });
  test(
    'resamples at radius divided by four and retains prototype timestamps',
    () {
      final result = arcSmooth(const [
        InkSample(0, 0, 0, 0),
        InkSample(4, 0, 0.5, 10),
        InkSample(8, 0, 1, 20),
      ], 4);
      expect(result.length, 10);
      expect(result[1].timeUs, 10);
      expect(result[6].timeUs, 20);
    },
  );
}
