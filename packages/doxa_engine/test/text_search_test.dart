// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/src/text/text_search.dart';
import 'package:test/test.dart';

/// One char per code point; char i is a 10 pt box on a line chosen by
/// [lineOf]; spaces have no box (like PDFium's generated chars).
PageText pageOf(String text, {int Function(int char)? lineOf}) {
  final runes = text.runes.toList();
  final boxes = Float64List(runes.length * 4);
  final unitToChar = <int>[];
  for (final (i, rune) in runes.indexed) {
    unitToChar.add(i);
    if (rune > 0xFFFF) unitToChar.add(i);
    if (rune == 0x20 || rune == 0x0A || rune == 0x0D) continue;
    final line = lineOf?.call(i) ?? 0;
    boxes
      ..[i * 4] = 72.0 + i * 10
      ..[i * 4 + 1] = 700.0 - line * 20
      ..[i * 4 + 2] = 80.0 + i * 10
      ..[i * 4 + 3] = 712.0 - line * 20;
  }
  return PageText(
    pageIndex: 3,
    text: text,
    charIndexOfUnit: Int32List.fromList(unitToChar),
    charBoxes: boxes,
  );
}

List<(int, int)> spans(String query, String text, {SearchQuery? options}) {
  final q = options ?? SearchQuery(query);
  return [
    for (final hit in TextMatcher(q).findAll(pageOf(text)))
      (hit.charIndex, hit.charCount),
  ];
}

void main() {
  group('fold tables', () {
    test('cover U+00C0–U+00FF and U+0100–U+017F', () {
      expect(latin1Bases, hasLength(0x40));
      expect(latinExtendedABases, hasLength(0x80));
    });

    test('map Portuguese letters to their bases', () {
      final folded = foldText(
        'ÁÉÍÓÚ ÂÊÔ ÃÕ À Ç áéíóú âêô ãõ à ç',
        matchCase: true,
        ignoreDiacritics: true,
      );
      expect(folded.text, 'AEIOU AEO AO A C aeiou aeo ao a c');
    });

    test('expand ligatures and sharp s', () {
      final folded = foldText(
        'Æ œ ß Ĳ',
        matchCase: false,
        ignoreDiacritics: true,
      );
      expect(folded.text, 'ae oe ss ij');
    });
  });

  group('foldText', () {
    test('collapses whitespace runs and keeps the source of each unit', () {
      final folded = foldText(
        'a \r\n\tb',
        matchCase: true,
        ignoreDiacritics: false,
      );
      expect(folded.text, 'a b');
      expect(folded.sourceUnit, [0, 1, 5]);
    });

    test('drops combining marks only when ignoring diacritics', () {
      const decomposed = 'ação';
      expect(
        foldText(decomposed, matchCase: true, ignoreDiacritics: true).text,
        'acao',
      );
      expect(
        foldText(decomposed, matchCase: true, ignoreDiacritics: false).text,
        decomposed,
      );
    });

    test('maps surrogate pairs back to their first unit', () {
      final folded = foldText('x😀y', matchCase: true, ignoreDiacritics: true);
      expect(folded.text, 'x😀y');
      expect(folded.sourceUnit, [0, 1, 1, 3]);
    });
  });

  group('TextMatcher', () {
    test('is diacritic- and case-insensitive by default (FR-TEXT-002)', () {
      expect(spans('acao', 'A Ação e a ação.'), [(2, 4), (11, 4)]);
      expect(spans('AÇÃO', 'acao'), [(0, 4)]);
    });

    test('finds composed text from a decomposed query and back', () {
      expect(spans('ação', 'ação'), [(0, 4)]);
      expect(spans('ação', 'ação'), [(0, 6)]);
    });

    test('honours match case', () {
      const options = SearchQuery('River', matchCase: true);
      expect(spans('', 'river River', options: options), [(6, 5)]);
    });

    test('keeps diacritics when asked', () {
      const options = SearchQuery('acao', ignoreDiacritics: false);
      expect(spans('', 'ação acao', options: options), [(5, 4)]);
    });

    test('honours whole word', () {
      const options = SearchQuery('art', wholeWord: true);
      expect(spans('', 'art, start, arte; art', options: options), [
        (0, 3),
        (18, 3),
      ]);
    });

    test('matches a phrase across a line break', () {
      expect(spans('marked the', 'marked\r\nthe river'), [(0, 11)]);
    });

    test('ignores empty queries', () {
      expect(TextMatcher(const SearchQuery('  ')).isEmpty, isTrue);
      expect(spans('  ', 'some text'), isEmpty);
    });

    test('reports non-overlapping hits', () {
      expect(spans('aa', 'aaaa'), [(0, 2), (2, 2)]);
    });

    test('counts chars, not code units, after a surrogate pair', () {
      expect(spans('y', 'x😀y'), [(2, 1)]);
    });

    test('treats letters outside the BMP as word chars', () {
      const options = SearchQuery('a', wholeWord: true);
      expect(spans('', 'a\u{1D431} \u{1D431}a a', options: options), [(6, 1)]);
    });

    test('returns one rectangle per line', () {
      final page = pageOf('one two', lineOf: (i) => i < 4 ? 0 : 1);
      final hits = TextMatcher(const SearchQuery('one two')).findAll(page);
      expect(hits.single.pageIndex, 3);
      expect(hits.single.rects, const [
        PdfRect(72, 700, 100, 712),
        PdfRect(112, 680, 140, 692),
      ]);
    });
  });
}
