// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

/// A point in PDF user space, where y grows upwards.
final class PdfPoint {
  const PdfPoint(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is PdfPoint && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
}

/// A PDF rectangle. Operations use normalized bounds; edges are included.
final class PdfRect {
  const PdfRect(this.left, this.bottom, this.right, this.top);
  final double left;
  final double bottom;
  final double right;
  final double top;

  double get width => (right - left).abs();
  double get height => (top - bottom).abs();
  PdfRect normalized() => PdfRect(
    math.min(left, right),
    math.min(bottom, top),
    math.max(left, right),
    math.max(bottom, top),
  );

  PdfRect union(PdfRect other) {
    final a = normalized();
    final b = other.normalized();
    return PdfRect(
      math.min(a.left, b.left),
      math.min(a.bottom, b.bottom),
      math.max(a.right, b.right),
      math.max(a.top, b.top),
    );
  }

  /// Touching edges intersect in a degenerate rectangle.
  PdfRect? intersect(PdfRect other) {
    final a = normalized();
    final b = other.normalized();
    final l = math.max(a.left, b.left);
    final r = math.min(a.right, b.right);
    final bottom = math.max(a.bottom, b.bottom);
    final t = math.min(a.top, b.top);
    return l <= r && bottom <= t ? PdfRect(l, bottom, r, t) : null;
  }

  /// Negative distances inset; an excessive inset collapses at the center.
  PdfRect inflate(double d) {
    final r = normalized();
    final dx = math.max(d, -r.width / 2);
    final dy = math.max(d, -r.height / 2);
    return PdfRect(r.left - dx, r.bottom - dy, r.right + dx, r.top + dy);
  }

  bool contains(PdfPoint point) {
    final r = normalized();
    return point.x >= r.left &&
        point.x <= r.right &&
        point.y >= r.bottom &&
        point.y <= r.top;
  }

  bool overlaps(PdfRect other) => intersect(other) != null;

  @override
  bool operator ==(Object other) =>
      other is PdfRect &&
      left == other.left &&
      bottom == other.bottom &&
      right == other.right &&
      top == other.top;
  @override
  int get hashCode => Object.hash(left, bottom, right, top);
}

/// Four points in /QuadPoints order: upper-left, upper-right,
/// lower-left, lower-right.
final class PdfQuad {
  const PdfQuad(this.p1, this.p2, this.p3, this.p4);
  factory PdfQuad.fromRect(PdfRect rect) {
    final r = rect.normalized();
    return PdfQuad(
      PdfPoint(r.left, r.top),
      PdfPoint(r.right, r.top),
      PdfPoint(r.left, r.bottom),
      PdfPoint(r.right, r.bottom),
    );
  }
  final PdfPoint p1;
  final PdfPoint p2;
  final PdfPoint p3;
  final PdfPoint p4;

  PdfRect get boundingRect => PdfRect(p1.x, p1.y, p1.x, p1.y)
      .union(PdfRect(p2.x, p2.y, p2.x, p2.y))
      .union(PdfRect(p3.x, p3.y, p3.x, p3.y))
      .union(PdfRect(p4.x, p4.y, p4.x, p4.y));
  List<double> toList() => [p1.x, p1.y, p2.x, p2.y, p3.x, p3.y, p4.x, p4.y];

  @override
  bool operator ==(Object other) =>
      other is PdfQuad &&
      p1 == other.p1 &&
      p2 == other.p2 &&
      p3 == other.p3 &&
      p4 == other.p4;
  @override
  int get hashCode => Object.hash(p1, p2, p3, p4);
}
