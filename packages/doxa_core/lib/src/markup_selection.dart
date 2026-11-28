// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'geometry.dart';

/// An extracted page and its selected half-open character range [start, end).
/// The caller supplies a range on each selected page, including full ranges
/// for intermediate pages. Character indices need not equal UTF-16 offsets.
typedef MarkupTextRange = ({
  int pageIndex,
  String text,
  List<int> charIndexOfUnit,
  List<double> charBoxes,
  List<double>? charAngles,
  int start,
  int end,
});

/// Geometry and text for one page's markup. Assign [text] to TextMarkup.text.
typedef MarkupPageSelection = ({
  int pageIndex,
  List<PdfQuad> quads,
  String text,
});

/// Builds markup for the supplied ranges in page order (FR-TEXT-005,
/// FR-MARK-001, FR-MARK-010). Boxes are left, bottom, right, top in PDF user
/// space, with all zeros for a missing box. Angles are counterclockwise radians
/// in the same space, independent of page display rotation. Null means zero.
List<MarkupPageSelection> buildMarkupSelection(
  Iterable<MarkupTextRange> ranges,
) => [
  for (final range
      in ranges.toList()..sort((a, b) => a.pageIndex.compareTo(b.pageIndex)))
    _selectPage(range),
];

final _lineBreak = RegExp(r'[\r\n]');
final _wrapHyphen = RegExp(r'(\p{L})[-\u00ad]\n(?=\p{L})', unicode: true);

MarkupPageSelection _selectPage(MarkupTextRange range) {
  final count = range.charBoxes.length ~/ 4;
  RangeError.checkValidRange(range.start, range.end, count);
  if (range.charBoxes.length % 4 != 0 ||
      range.charIndexOfUnit.length != range.text.length ||
      (range.charAngles != null && range.charAngles!.length != count)) {
    throw ArgumentError('Text layer arrays do not match');
  }

  final fragments = <_Fragment>[];
  var unit = 0;
  while (unit < range.text.length &&
      range.charIndexOfUnit[unit] < range.start) {
    unit++;
  }
  for (var char = range.start; char < range.end; char++) {
    final startUnit = unit;
    while (unit < range.text.length && range.charIndexOfUnit[unit] == char) {
      unit++;
    }
    final offset = char * 4;
    final box = PdfRect(
      range.charBoxes[offset],
      range.charBoxes[offset + 1],
      range.charBoxes[offset + 2],
      range.charBoxes[offset + 3],
    ).normalized();
    if (box.width == 0 && box.height == 0) continue;

    final angle = range.charAngles?[char] ?? 0;
    final previous = fragments.lastOrNull;
    if (previous != null &&
        !_lineBreak.hasMatch(
          range.text.substring(previous.endUnit, startUnit),
        ) &&
        previous.tryAppend(box, angle, unit)) {
      continue;
    }
    fragments.add(_Fragment(box, angle, startUnit, unit));
  }

  final ordered = _readingOrder(fragments);
  final text = ordered
      .map((line) => range.text.substring(line.startUnit, line.endUnit).trim())
      .where((line) => line.isNotEmpty)
      .join('\n')
      .replaceAllMapped(_wrapHyphen, (match) => match[1]!);
  return (
    pageIndex: range.pageIndex,
    quads: [for (final line in ordered) line.quad],
    text: text,
  );
}

/// For horizontal text, a strip of whitespace running through the selected
/// fragments can divide columns. Keep source order for rotated layouts.
List<_Fragment> _readingOrder(List<_Fragment> lines) {
  if (lines.length < 2 ||
      lines.any((line) => line.cosine < 0.999999 || line.sine.abs() > 0.001)) {
    return lines;
  }
  final byLeft = lines.toList()
    ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
  final columns = <List<_Fragment>>[];
  var right = double.negativeInfinity;
  for (final line in byLeft) {
    // A gap wider than two line heights is unlikely to be word spacing.
    if (line.bounds.left - right > 2 * line.bounds.height) {
      columns.add([]);
      right = line.bounds.right;
    }
    columns.last.add(line);
    right = math.max(right, line.bounds.right);
  }

  // Disjoint indented lines at different heights do not form columns.
  if (columns.length < 2 ||
      !columns.asMap().entries.skip(1).every((entry) {
        final a = columns[entry.key - 1]
            .map((line) => line.bounds)
            .reduce((a, b) => a.union(b));
        final b = entry.value
            .map((line) => line.bounds)
            .reduce((a, b) => a.union(b));
        return math.min(a.top, b.top) > math.max(a.bottom, b.bottom);
      })) {
    return lines;
  }
  return [
    for (final column in columns)
      ...(column..sort((a, b) => a.startUnit.compareTo(b.startUnit))),
  ];
}

final class _Fragment {
  _Fragment(PdfRect box, this.angle, this.startUnit, this.endUnit)
    : cosine = math.cos(angle),
      sine = math.sin(angle) {
    bounds = _project(box);
    _previous = bounds;
  }

  final double angle;
  final double cosine;
  final double sine;
  final int startUnit;
  int endUnit;
  late PdfRect bounds;
  late PdfRect _previous;

  bool tryAppend(PdfRect box, double nextAngle, int nextEnd) {
    // Compare wrapped angles, allowing for PDFium's float rounding.
    if (math.cos(nextAngle - angle) < 0.999999) return false;
    final next = _project(box);
    final overlap =
        math.min(_previous.top, next.top) -
        math.max(_previous.bottom, next.bottom);
    final gap =
        math.max(_previous.left, next.left) -
        math.min(_previous.right, next.right);
    // Compare with the previous glyph so the accumulated envelope cannot
    // pull in the following line. Relative overlap permits mixed font sizes.
    if (overlap < 0.5 * math.min(_previous.height, next.height) ||
        gap > 2 * math.max(_previous.height, next.height)) {
      return false;
    }
    bounds = bounds.union(next);
    _previous = next;
    endUnit = nextEnd;
    return true;
  }

  PdfRect _project(PdfRect box) {
    if (angle == 0) return box;
    // Project the centre and half extents of the user-space bounding box.
    // For oblique text this is conservative: the original oriented glyph
    // corners cannot in general be recovered from an axis-aligned box.
    final x = (box.left + box.right) / 2;
    final y = (box.bottom + box.top) / 2;
    final along = x * cosine + y * sine;
    final across = -x * sine + y * cosine;
    final halfWidth = (box.width * cosine.abs() + box.height * sine.abs()) / 2;
    final halfHeight = (box.width * sine.abs() + box.height * cosine.abs()) / 2;
    return PdfRect(
      along - halfWidth,
      across - halfHeight,
      along + halfWidth,
      across + halfHeight,
    );
  }

  PdfQuad get quad {
    PdfPoint toUser(double x, double y) =>
        PdfPoint(x * cosine - y * sine, x * sine + y * cosine);
    return PdfQuad(
      toUser(bounds.left, bounds.top),
      toUser(bounds.right, bounds.top),
      toUser(bounds.left, bounds.bottom),
      toUser(bounds.right, bounds.bottom),
    );
  }
}
