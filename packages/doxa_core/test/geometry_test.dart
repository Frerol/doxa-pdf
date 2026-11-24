// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:doxa_core/doxa_core.dart';
import 'package:test/test.dart';

void main() {
  const r = PdfRect(1, 2, 5, 8);
  test('T-03 point value equality and hash', () {
    expect(const PdfPoint(1, 2), const PdfPoint(1, 2));
    expect(const PdfPoint(1, 2).hashCode, const PdfPoint(1, 2).hashCode);
    expect(const PdfPoint(1, 2), isNot(const PdfPoint(2, 1)));
    expect(const PdfPoint(1, 2) == Object(), isFalse);
  });
  test('T-03 rect value equality and hash', () {
    expect(r, const PdfRect(1, 2, 5, 8));
    expect(r.hashCode, const PdfRect(1, 2, 5, 8).hashCode);
    expect(r, isNot(const PdfRect(1, 2, 5, 9)));
    expect(r == Object(), isFalse);
  });
  test('T-03 normalization and dimensions', () {
    const reversed = PdfRect(5, 8, 1, 2);
    expect(reversed.normalized(), r);
    expect(r.normalized(), r);
    expect(reversed.width, 4);
    expect(reversed.height, 6);
  });
  test('T-03 union and intersection', () {
    const other = PdfRect(3, 4, 9, 10);
    expect(r.union(other), const PdfRect(1, 2, 9, 10));
    expect(r.intersect(other), const PdfRect(3, 4, 5, 8));
    expect(r.intersect(const PdfRect(10, 10, 11, 11)), isNull);
    expect(r.intersect(const PdfRect(5, 2, 7, 8)), const PdfRect(5, 2, 5, 8));
  });
  test('T-03 inflation and inset', () {
    expect(r.inflate(2), const PdfRect(-1, 0, 7, 10));
    expect(r.inflate(-1), const PdfRect(2, 3, 4, 7));
    expect(r.inflate(-100), const PdfRect(3, 5, 3, 5));
  });
  test('T-03 containment and overlap include boundaries', () {
    expect(r.contains(const PdfPoint(1, 8)), isTrue);
    expect(r.contains(const PdfPoint(0, 8)), isFalse);
    expect(r.overlaps(const PdfRect(5, 2, 7, 8)), isTrue);
    expect(r.overlaps(const PdfRect(6, 2, 7, 8)), isFalse);
    expect(const PdfRect(5, 8, 1, 2).contains(const PdfPoint(3, 4)), isTrue);
  });
  test('T-03 degenerate rectangles', () {
    const point = PdfRect(2, 3, 2, 3);
    expect(point.width, 0);
    expect(point.height, 0);
    expect(point.contains(const PdfPoint(2, 3)), isTrue);
    expect(point.intersect(r), point);
    expect(point.union(point), point);
    expect(point.inflate(1), const PdfRect(1, 2, 3, 4));
  });
  test('T-03 quad order, bounds and value equality', () {
    final quad = PdfQuad.fromRect(r);
    expect(quad.toList(), [1.0, 8.0, 5.0, 8.0, 1.0, 2.0, 5.0, 2.0]);
    expect(quad.boundingRect, r);
    expect(quad, PdfQuad.fromRect(const PdfRect(5, 8, 1, 2)));
    expect(quad.hashCode, PdfQuad.fromRect(r).hashCode);
    expect(quad == Object(), isFalse);
    expect(
      PdfQuad.fromRect(const PdfRect(2, 3, 2, 3)).boundingRect,
      const PdfRect(2, 3, 2, 3),
    );
  });
  test('T-03 arbitrary quad bounds', () {
    const quad = PdfQuad(
      PdfPoint(3, 9),
      PdfPoint(7, 8),
      PdfPoint(-1, 2),
      PdfPoint(4, -3),
    );
    expect(quad.boundingRect, const PdfRect(-1, -3, 7, 9));
  });
}
