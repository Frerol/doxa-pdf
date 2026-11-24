// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:doxa_core/doxa_core.dart';
import 'package:test/test.dart';

void main() {
  test('T-01 UTC formatting and round trip', () {
    final date = DateTime.utc(2026, 11, 24, 12);
    expect(formatPdfDate(date), 'D:20261124120000Z');
    expect(parsePdfDate(formatPdfDate(date)), date);
    expect(
      formatPdfDate(DateTime.parse('2026-11-24T15:00:00+03:00')),
      formatPdfDate(date),
    );
  });
  test('T-01 all truncations and optional prefix', () {
    final expected = [
      DateTime.utc(2026),
      DateTime.utc(2026, 11),
      DateTime.utc(2026, 11, 24),
      DateTime.utc(2026, 11, 24, 12),
      DateTime.utc(2026, 11, 24, 12, 30),
      DateTime.utc(2026, 11, 24, 12, 30, 45),
    ];
    for (var i = 0; i < expected.length; i++) {
      final text = '20261124123045'.substring(0, 4 + 2 * i);
      expect(parsePdfDate(text), expected[i]);
      expect(parsePdfDate('D:${text}Z'), expected[i]);
    }
  });
  test('T-01 positive and negative offsets cross dates', () {
    expect(
      parsePdfDate("D:20260101010000+02'30'"),
      DateTime.utc(2025, 12, 31, 22, 30),
    );
    expect(
      parsePdfDate("20260101230000-02'30"),
      DateTime.utc(2026, 1, 2, 1, 30),
    );
    expect(parsePdfDate('2026+02'), DateTime.utc(2025, 12, 31, 22));
  });
  test('T-01 invalid input never throws', () {
    for (final text in [
      '',
      'letters',
      'D:',
      '20261',
      '202613',
      '202600',
      '20260229',
      '20260431',
      '2026010124',
      '202601010060',
      '20260101000060',
      "2026+24'00'",
      "2026+01'60'",
      '2026Z\n',
      '202601010000001',
      '2026+0100',
    ]) {
      expect(parsePdfDate(text), isNull, reason: text);
    }
    expect(parsePdfDate('20240229'), DateTime.utc(2024, 2, 29));
  });
}
