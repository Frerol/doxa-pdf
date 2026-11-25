// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_controller.dart';

/// A selected range of chars on one page; [first] <= [last].
final class SelectedText {
  const SelectedText(this.page, this.first, this.last);
  final int page;
  final int first;
  final int last;
}

final _wordChar = RegExp(r'[\p{L}\p{N}\p{M}_]', unicode: true);

/// Text selection on one page (FR-TEXT-004): a long press selects the word
/// under the finger, dragging extends it, and the handles at both ends move
/// its start and end. The selection is highlighted through [reader].
///
/// Selection across pages and in reading order across columns is
/// FR-TEXT-005 (M2).
final class TextSelectionController {
  TextSelectionController(this.reader);

  final ReaderController reader;
  final selection = ValueNotifier<SelectedText?>(null);
  PageText? _text;

  /// The word the long press selected; a drag grows the selection from it
  /// in both directions.
  (int, int)? _word;

  /// The end that stays put while a handle is dragged.
  int? _fixed;

  /// A long press is still loading its page text; drags wait for it.
  bool _pending = false;
  bool _disposed = false;

  bool get hasSelection => selection.value != null;

  /// Selects the word at [screenPoint]. Returns false when there is no
  /// text there (for example, on a scanned page; FR-TEXT-007 is M2).
  Future<bool> selectWordAt(Offset screenPoint) async {
    clear();
    _pending = true;
    final hit = await _charAt(screenPoint);
    _pending = false;
    if (_disposed || hit == null) return false;
    final (text, char) = hit;
    _text = text;
    final (first, last) = _wordAround(text, char);
    _word = (first, last);
    _set(SelectedText(text.pageIndex, first, last));
    return true;
  }

  /// Extends the selection from the long-pressed word to the char at
  /// [screenPoint], keeping the whole word.
  Future<void> extendTo(Offset screenPoint) async {
    final current = selection.value;
    final word = _word;
    if (_pending || current == null || word == null) return;
    final char = _nearestChar(current.page, screenPoint);
    if (char == null) return;
    final (first, last) = word;
    _set(
      SelectedText(current.page, math.min(first, char), math.max(last, char)),
    );
  }

  /// Starts dragging the start or end handle: the other end stays put for
  /// the whole drag, even when the dragged end passes it.
  void beginHandleDrag({required bool start}) {
    final current = selection.value;
    _fixed = current == null ? null : (start ? current.last : current.first);
  }

  /// Moves the dragged end of the selection to the char at [screenPoint].
  void moveHandle({required bool start, required Offset screenPoint}) {
    final current = selection.value;
    if (current == null) return;
    final char = _nearestChar(current.page, screenPoint);
    if (char == null) return;
    final fixed = _fixed ?? (start ? current.last : current.first);
    _set(
      SelectedText(current.page, math.min(fixed, char), math.max(fixed, char)),
    );
  }

  /// The selected text, ready for the clipboard.
  String get text {
    final current = selection.value;
    final pageText = _text;
    if (current == null || pageText == null) return '';
    final units = pageText.charIndexOfUnit;
    var start = 0;
    while (start < units.length && units[start] < current.first) {
      start++;
    }
    var end = start;
    while (end < units.length && units[end] <= current.last) {
      end++;
    }
    return pageText.text
        .substring(start, end)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
  }

  /// Screen positions of the start and end handles: the bottom-left of the
  /// first char and the bottom-right of the last one.
  (Offset, Offset)? handles() {
    final current = selection.value;
    final pageText = _text;
    if (current == null || pageText == null) return null;
    final rects = lineRects(
      pageText,
      current.first,
      current.last - current.first + 1,
    );
    if (rects.isEmpty) return null;
    final first = reader.documentRect(current.page, rects.first);
    final last = reader.documentRect(current.page, rects.last);
    if (first == null || last == null) return null;
    Offset toScreen(Offset doc) => (doc - reader.offset) * reader.zoom;
    return (toScreen(first.bottomLeft), toScreen(last.bottomRight));
  }

  /// Screen rectangle around the selected lines, for placing the
  /// selection toolbar; null when nothing is selected.
  Rect? bounds() {
    final current = selection.value;
    final pageText = _text;
    if (current == null || pageText == null) return null;
    Rect? union;
    for (final rect in lineRects(
      pageText,
      current.first,
      current.last - current.first + 1,
    )) {
      final doc = reader.documentRect(current.page, rect);
      if (doc == null) continue;
      final screen = Rect.fromPoints(
        (doc.topLeft - reader.offset) * reader.zoom,
        (doc.bottomRight - reader.offset) * reader.zoom,
      );
      union = union == null ? screen : union.expandToInclude(screen);
    }
    return union;
  }

  void clear() {
    _word = null;
    _fixed = null;
    if (_disposed || selection.value == null) return;
    selection.value = null;
    reader.setHighlights(HighlightLayer.selection, const {});
  }

  void dispose() {
    _disposed = true;
    selection.dispose();
  }

  void _set(SelectedText value) {
    selection.value = value;
    final pageText = _text!;
    reader.setHighlights(HighlightLayer.selection, {
      value.page: lineRects(
        pageText,
        value.first,
        value.last - value.first + 1,
      ),
    });
  }

  Future<(PageText, int)?> _charAt(Offset screenPoint) async {
    final layout = reader.layout;
    if (layout == null || layout.pageCount == 0) return null;
    final point = reader.toDocument(screenPoint);
    final page = layout.pageAt(point);
    if (!layout.pageRect(page).contains(point)) return null;
    try {
      await reader.pageDetails(page);
      final text = await reader.engine.pageText(reader.document, page);
      final user = reader.userPoint(page, point);
      if (user == null) return null;
      final char = _closestChar(text, user, maxDistance: 12);
      return char == null ? null : (text, char);
    } on PdfEngineException {
      return null;
    }
  }

  int? _nearestChar(int page, Offset screenPoint) {
    final pageText = _text;
    if (pageText == null) return null;
    final user = reader.userPoint(page, reader.toDocument(screenPoint));
    if (user == null) return null;
    return _closestChar(pageText, user);
  }

  /// The char whose box contains [point], or the closest one (vertical
  /// distance counts more, so the same line wins), within [maxDistance]
  /// points when given.
  static int? _closestChar(
    PageText text,
    PdfPoint point, {
    double? maxDistance,
  }) {
    int? best;
    var bestScore = double.infinity;
    for (var i = 0; i < text.charCount; i++) {
      final box = text.charBox(i)?.normalized();
      if (box == null) continue;
      if (box.contains(point)) return i;
      final dx = point.x < box.left
          ? box.left - point.x
          : (point.x > box.right ? point.x - box.right : 0.0);
      final dy = point.y < box.bottom
          ? box.bottom - point.y
          : (point.y > box.top ? point.y - box.top : 0.0);
      if (maxDistance != null && math.max(dx, dy) > maxDistance) continue;
      final score = dx + dy * 4;
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  /// The word around [char], or [char] alone when it is not a word char.
  static (int, int) _wordAround(PageText text, int char) {
    bool isWord(int c) {
      if (c < 0 || c >= text.charCount) return false;
      final unit = text.charIndexOfUnit.indexOf(c);
      return unit >= 0 && _wordChar.hasMatch(text.text[unit]);
    }

    if (!isWord(char)) return (char, char);
    var first = char, last = char;
    while (isWord(first - 1)) {
      first--;
    }
    while (isWord(last + 1)) {
      last++;
    }
    return (first, last);
  }
}
