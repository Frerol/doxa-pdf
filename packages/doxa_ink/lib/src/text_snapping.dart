// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:doxa_core/doxa_core.dart';

/// Minimum share of centreline length tracking text. Two thirds leaves room
/// for a line transition or small overshoot while requiring text to dominate.
const minTextSnapCoverage = 2 / 3;

/// A half-open range of indices into the input character boxes.
typedef TextSnapRange = ({int start, int endExclusive});

/// Finds the text covered by a finished pen stroke (FR-MARK-013).
///
/// Supply [charBoxes] in page text order, preserving null entries for chars
/// without a box. Both inputs use PDF user space with horizontal text lines.
/// On a rotated display, map pointer coordinates with [PageTransform.toUser]
/// before constructing the stroke. The returned range includes any intervening
/// spaces and line breaks. Null means the stroke stays ink.
///
/// Coverage is measured along the polyline, independently of sample density.
/// A qualifying path tracks one line or visits consecutive lines in order
/// (forward or backward), with predominantly one direction on each line.
TextSnapRange? snapStrokeToText(InkStroke stroke, List<PdfRect?> charBoxes) {
  final points = stroke.points;
  if (points.length < 2 || points.any((p) => !p.x.isFinite || !p.y.isFinite)) {
    return null;
  }
  final lines = _textLines(charBoxes);
  var length = 0.0, covered = 0.0;
  var first = charBoxes.length, last = -1;
  int? firstLine, previousLine;
  int? lineStep, verticalStep;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    final dx = b.x - a.x, dy = b.y - a.y;
    final segmentLength = math.sqrt(dx * dx + dy * dy);
    length += segmentLength;
    // A transition across lines contributes to total length only.
    if (dx == 0 || dx.abs() < 2 * dy.abs()) continue;

    // Overlapping glyph bounds may give two candidates. Count the segment
    // only once, in the line that covers the largest share of it.
    var bestShare = 0.0, fromX = 0.0, toX = 0.0;
    var bestLine = -1;
    for (var j = 0; j < lines.length; j++) {
      final clip = _clip(a, dx, dy, lines[j].bounds);
      if (clip == null) continue;
      final (from, to) = clip;
      if (to - from <= bestShare) continue;
      bestShare = to - from;
      bestLine = j;
      fromX = a.x + from * dx;
      toX = a.x + to * dx;
    }
    if (bestLine == -1) continue;
    if (previousLine != null && bestLine != previousLine) {
      final step = bestLine - previousLine;
      if (step.abs() != 1 || (lineStep != null && step != lineStep)) {
        return null;
      }
      final before = lines[previousLine].bounds;
      final after = lines[bestLine].bounds;
      final rise =
          after.bottom + after.height / 2 - (before.bottom + before.height / 2);
      final direction = rise > 0 ? 1 : -1;
      if (rise.abs() < math.min(before.height, after.height) / 2 ||
          (verticalStep != null && direction != verticalStep)) {
        return null;
      }
      lineStep = step;
      verticalStep = direction;
    }
    firstLine ??= bestLine;
    previousLine = bestLine;
    final line = lines[bestLine];
    final advance = toX - fromX;
    line.travel += advance.abs();
    line.advance += advance;
    covered += bestShare * segmentLength;
    final left = math.min(fromX, toX), right = math.max(fromX, toX);
    for (final (index, box) in line.chars) {
      if (left < box.right && right > box.left) {
        first = math.min(first, index);
        last = math.max(last, index);
      }
    }
  }
  if (last < first || covered < minTextSnapCoverage * length) return null;

  // Allow small corrections in direction, but reject loops and retracing.
  if (lines.any((line) => line.advance.abs() < 0.75 * line.travel)) {
    return null;
  }
  final dx = points.last.x - points.first.x;
  final dy = points.last.y - points.first.y;
  // A loop can trace different lines in opposite directions. Its endpoints
  // still stay close compared with the height of the starting text line.
  final closingDistance = math.min(
    0.1 * length,
    lines[firstLine!].bounds.height / 2,
  );
  if (math.sqrt(dx * dx + dy * dy) < closingDistance) return null;
  return (start: first, endExclusive: last + 1);
}

final class _TextLine {
  _TextLine(this.bounds);

  PdfRect bounds;
  final chars = <(int, PdfRect)>[];
  double advance = 0;
  double travel = 0;
}

List<_TextLine> _textLines(List<PdfRect?> boxes) {
  final lines = <_TextLine>[];
  PdfRect? previous;
  for (var i = 0; i < boxes.length; i++) {
    final box = boxes[i]?.normalized();
    if (box == null ||
        box.width <= 0 ||
        box.height <= 0 ||
        !box.width.isFinite ||
        !box.height.isFinite) {
      continue;
    }
    if (previous == null || !_sameLine(previous, box)) {
      lines.add(_TextLine(box));
    }
    final line = lines.last;
    line.bounds = line.bounds.union(box);
    line.chars.add((i, box));
    previous = box;
  }
  return lines;
}

bool _sameLine(PdfRect a, PdfRect b) {
  final overlap = math.min(a.top, b.top) - math.max(a.bottom, b.bottom);
  final gap = math.max(a.left, b.left) - math.min(a.right, b.right);
  // Bridge ordinary word spaces without spanning a wide column gutter.
  return overlap >= math.min(a.height, b.height) / 2 &&
      gap <= 2 * math.max(a.height, b.height);
}

/// Clips a segment to a line's bounds, returning fractions along the segment.
/// The caller supplies a nonzero horizontal component.
(double, double)? _clip(PdfPoint a, double dx, double dy, PdfRect bounds) {
  final x1 = (bounds.left - a.x) / dx, x2 = (bounds.right - a.x) / dx;
  var from = math.max(0.0, math.min(x1, x2));
  var to = math.min(1.0, math.max(x1, x2));
  if (dy == 0) {
    if (a.y < bounds.bottom || a.y > bounds.top) return null;
  } else {
    final y1 = (bounds.bottom - a.y) / dy, y2 = (bounds.top - a.y) / dy;
    from = math.max(from, math.min(y1, y2));
    to = math.min(to, math.max(y1, y2));
  }
  return from < to ? (from, to) : null;
}
