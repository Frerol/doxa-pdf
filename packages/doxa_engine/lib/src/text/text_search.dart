// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:doxa_core/doxa_core.dart';

import '../api/types.dart';

/// Text after case and diacritic folding, with the source UTF-16 unit that
/// produced each folded unit.
final class FoldedText {
  const FoldedText(this.text, this.sourceUnit);
  final String text;
  final Int32List sourceUnit;
}

/// Folds [input] for matching: every whitespace run becomes one space,
/// diacritics are removed when [ignoreDiacritics] is set (Latin-1 Supplement
/// and Latin Extended-A letters, plus combining marks U+0300–U+036F), and
/// letters are lowercased unless [matchCase] is set.
FoldedText foldText(
  String input, {
  required bool matchCase,
  required bool ignoreDiacritics,
}) {
  final out = StringBuffer();
  final source = <int>[];
  var unit = 0;
  var inSpace = false;
  for (final rune in input.runes) {
    final start = unit;
    unit += rune > 0xFFFF ? 2 : 1;
    if (_isSpace(rune)) {
      if (!inSpace) {
        out.writeCharCode(0x20);
        source.add(start);
        inSpace = true;
      }
      continue;
    }
    inSpace = false;
    if (ignoreDiacritics && rune >= 0x300 && rune <= 0x36F) continue;
    var folded = ignoreDiacritics ? _baseLetters(rune) : null;
    folded ??= String.fromCharCode(rune);
    if (!matchCase) folded = folded.toLowerCase();
    out.write(folded);
    for (var i = 0; i < folded.length; i++) {
      source.add(start);
    }
  }
  return FoldedText(out.toString(), Int32List.fromList(source));
}

bool _isSpace(int rune) =>
    rune == 0x20 ||
    (rune >= 0x09 && rune <= 0x0D) ||
    rune == 0xA0 ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x3000 ||
    (rune >= 0x2000 && rune <= 0x200A);

String? _baseLetters(int rune) {
  if (rune >= 0xC0 && rune <= 0xFF) return latin1Bases[rune - 0xC0];
  if (rune >= 0x100 && rune <= 0x17F) return latinExtendedABases[rune - 0x100];
  return null;
}

/// Base letters of U+00C0–U+00FF. Signs without a base map to themselves.
const latin1Bases = [
  'A', 'A', 'A', 'A', 'A', 'A', 'AE', 'C', 'E', 'E', 'E', 'E', 'I', 'I', //
  'I', 'I', 'D', 'N', 'O', 'O', 'O', 'O', 'O', '×', 'O', 'U', 'U', //
  'U', 'U', 'Y', 'Þ', 'ss', //
  'a', 'a', 'a', 'a', 'a', 'a', 'ae', 'c', 'e', 'e', 'e', 'e', 'i', 'i', //
  'i', 'i', 'd', 'n', 'o', 'o', 'o', 'o', 'o', '÷', 'o', 'u', 'u', //
  'u', 'u', 'y', 'þ', 'y', //
];

/// Base letters of U+0100–U+017F.
const latinExtendedABases = [
  'A', 'a', 'A', 'a', 'A', 'a', 'C', 'c', 'C', 'c', 'C', 'c', 'C', 'c', //
  'D', 'd', 'D', 'd', 'E', 'e', 'E', 'e', 'E', 'e', 'E', 'e', 'E', 'e', //
  'G', 'g', 'G', 'g', 'G', 'g', 'G', 'g', 'H', 'h', 'H', 'h', //
  'I', 'i', 'I', 'i', 'I', 'i', 'I', 'i', 'I', 'i', 'IJ', 'ij', 'J', 'j', //
  'K', 'k', 'ĸ', 'L', 'l', 'L', 'l', 'L', 'l', 'L', 'l', 'L', 'l', //
  'N', 'n', 'N', 'n', 'N', 'n', 'ʼn', 'Ŋ', 'ŋ', //
  'O', 'o', 'O', 'o', 'O', 'o', 'OE', 'oe', 'R', 'r', 'R', 'r', 'R', 'r', //
  'S', 's', 'S', 's', 'S', 's', 'S', 's', 'T', 't', 'T', 't', 'T', 't', //
  'U', 'u', 'U', 'u', 'U', 'u', 'U', 'u', 'U', 'u', 'U', 'u', 'W', 'w', //
  'Y', 'y', 'Y', 'Z', 'z', 'Z', 'z', 'Z', 'z', 's', //
];

final _wordChar = RegExp(r'[\p{L}\p{N}\p{M}_]', unicode: true);

/// Finds the hits of one [SearchQuery] in page text layers.
final class TextMatcher {
  TextMatcher(this.query)
    : _needle = foldText(
        query.text,
        matchCase: query.matchCase,
        ignoreDiacritics: query.ignoreDiacritics,
      ).text.trim();

  final SearchQuery query;
  final String _needle;

  /// True when the query has nothing to find (empty or only spaces).
  bool get isEmpty => _needle.isEmpty;

  List<SearchHit> findAll(PageText page) {
    if (isEmpty) return const [];
    final folded = foldText(
      page.text,
      matchCase: query.matchCase,
      ignoreDiacritics: query.ignoreDiacritics,
    );
    final haystack = folded.text;
    final hits = <SearchHit>[];
    var from = 0;
    while (true) {
      final at = haystack.indexOf(_needle, from);
      if (at < 0) break;
      final end = at + _needle.length;
      if (query.wholeWord && !_isWholeWord(haystack, at, end)) {
        from = at + 1;
        continue;
      }
      final first = page.charIndexOfUnit[folded.sourceUnit[at]];
      final last = page.charIndexOfUnit[folded.sourceUnit[end - 1]];
      hits.add(
        SearchHit(
          pageIndex: page.pageIndex,
          charIndex: first,
          charCount: last - first + 1,
          rects: lineRects(page, first, last - first + 1),
        ),
      );
      from = end;
    }
    return hits;
  }

  static bool _isWholeWord(String text, int start, int end) {
    // Read whole code points, so letters outside the BMP count as letters.
    bool isWordAt(int from, int to) =>
        from >= 0 &&
        to <= text.length &&
        _wordChar.hasMatch(text.substring(from, to));
    final before =
        start >= 2 &&
            _isLowUnit(text, start - 1) &&
            _isHighUnit(text, start - 2)
        ? isWordAt(start - 2, start)
        : isWordAt(start - 1, start);
    final after = _isHighUnit(text, end) && _isLowUnit(text, end + 1)
        ? isWordAt(end, end + 2)
        : isWordAt(end, end + 1);
    return !before && !after;
  }

  static bool _isHighUnit(String text, int i) =>
      i >= 0 && i < text.length && (text.codeUnitAt(i) & 0xFC00) == 0xD800;
  static bool _isLowUnit(String text, int i) =>
      i >= 0 && i < text.length && (text.codeUnitAt(i) & 0xFC00) == 0xDC00;
}

/// Merges the boxes of chars `[first, first + count)` into one rectangle
/// per line, skipping chars without a box.
List<PdfRect> lineRects(PageText page, int first, int count) {
  final rects = <PdfRect>[];
  PdfRect? line;
  for (var i = first; i < first + count; i++) {
    final box = page.charBox(i)?.normalized();
    if (box == null) continue;
    if (line != null && _sameLine(line, box)) {
      line = line.union(box);
    } else {
      if (line != null) rects.add(line);
      line = box;
    }
  }
  if (line != null) rects.add(line);
  return rects;
}

/// Same line when the box's vertical centre falls inside the line so far.
bool _sameLine(PdfRect line, PdfRect box) {
  final centre = (box.bottom + box.top) / 2;
  return centre >= line.bottom && centre <= line.top;
}
