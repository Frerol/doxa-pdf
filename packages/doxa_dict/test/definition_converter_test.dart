// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:test/test.dart';

DefinitionResult _convert(String type, String source) => convertDefinition(
  DictionaryField.parse(
    Uint8List.fromList(utf8.encode(source)),
    sameTypeSequence: type,
  ),
);

DefinitionBlock _paragraph(List<DefinitionSpan> spans) =>
    DefinitionBlock(DefinitionBlockKind.paragraph, spans);

DefinitionBlock _item(String text) =>
    DefinitionBlock(DefinitionBlockKind.listItem, [DefinitionSpan(text)]);

void main() {
  group('FR-TEXT-010 field conversion', () {
    for (final type in ['m', 't', 'y']) {
      test('$type preserves literal markup and converts newlines', () {
        expect(_convert(type, '<b>&amp;</b>\r\nnext\rlast\n').blocks, [
          _paragraph(const [
            DefinitionSpan('<b>&amp;</b>'),
            DefinitionSpan.lineBreak(),
            DefinitionSpan('next'),
            DefinitionSpan.lineBreak(),
            DefinitionSpan('last'),
            DefinitionSpan.lineBreak(),
          ]),
        ]);
      });
    }

    test('g strips Pango tags and keeps their plain text', () {
      expect(
        _convert('g', '<span size="large"><b>head</b></span> &amp;').blocks,
        [
          _paragraph(const [DefinitionSpan('head &')]),
        ],
      );
    });

    test(
      'supported fields stay in order around skipped binary and text fields',
      () {
        final fields = DictionaryField.parse(
          Uint8List.fromList([65, 0, 0, 0, 0, 1, 255, 66, 0, 67]),
          sameTypeSequence: 'mWzt',
        );
        final result = convertDefinition(fields);
        expect(result.unsupportedFields, 2);
        expect(result.blocks, [
          _paragraph(const [DefinitionSpan('A')]),
          _paragraph(const [DefinitionSpan('C')]),
        ]);
        expect(result.blocks.clear, throwsUnsupportedError);
        expect(result.blocks.first.spans.clear, throwsUnsupportedError);
      },
    );
  });

  group('ADR-0009 markup reduction', () {
    test('HTML preserves the paragraph, emphasis and list whitelist', () {
      final result = _convert(
        'h',
        '<P><b>bold</b>, <strong><i>both</i></strong> '
            '<em>italic</em><br/>next</P>'
            '<ul><li>one</li></ul><ol><li>two</li><li>three</li></ol>',
      );
      expect(result.blocks, [
        _paragraph(const [
          DefinitionSpan('bold', bold: true),
          DefinitionSpan(', '),
          DefinitionSpan('both', bold: true, italic: true),
          DefinitionSpan(' '),
          DefinitionSpan('italic', italic: true),
          DefinitionSpan.lineBreak(),
          DefinitionSpan('next'),
        ]),
        _item('one'),
        _item('two'),
        _item('three'),
      ]);
    });

    test('nested lists retain the enclosing item around a sublist', () {
      expect(_convert('h', '<ul><li>a<ul><li>b</li></ul>c</li></ul>').blocks, [
        _item('a'),
        _item('b'),
        _item('c'),
      ]);
    });

    test(
      'HTML discards script and style bodies with mixed case and attributes',
      () {
        expect(
          _convert(
            'h',
            'before<SCRIPT data-x=">">if (x < y) { "<b>hidden"; }</sCrIpT >'
                '<STYLE media="screen">.hidden { content: "secret"; }</STYLE>after',
          ).blocks,
          [
            _paragraph(const [DefinitionSpan('beforeafter')]),
          ],
        );
      },
    );

    test(
      'link text and other visible text survive without external references',
      () {
        expect(
          _convert(
            'h',
            '<section>see <a href="https://example.invalid/?a=>">entry</a>'
                '<img src="https://example.invalid/image"> now</section>',
          ).blocks,
          [
            _paragraph(const [DefinitionSpan('see entry now')]),
          ],
        );
      },
    );

    test('XDXF maps headings, block quotes, emphasis and plain tags', () {
      expect(
        _convert(
          'x',
          '<k>headword</k><blockquote><b>bold</b> <i>italic</i> '
              '<ex>example</ex> <abr>abbr</abr> '
              '<c>color</c> <kref>reference</kref> <dtrn>translation</dtrn> '
              '<co>comment</co> <other>other</other></blockquote>',
        ).blocks,
        [
          _paragraph(const [DefinitionSpan('headword', bold: true)]),
          _paragraph(const [
            DefinitionSpan('bold', bold: true),
            DefinitionSpan(' '),
            DefinitionSpan('italic', italic: true),
            DefinitionSpan(' '),
            DefinitionSpan('example', italic: true),
            DefinitionSpan(' '),
            DefinitionSpan('abbr', italic: true),
            DefinitionSpan(' color reference translation comment other'),
          ]),
        ],
      );
    });
  });

  group('FR-TEXT-010 entities', () {
    test('decodes the supported names and valid Unicode references once', () {
      expect(
        _convert(
          'h',
          '&amp;&lt;&gt;&quot;&apos;&nbsp;&ndash;&mdash;&hellip;'
              '&laquo;&raquo;&copy; &#65;&#x1F600;&#X10FFFF; &amp;lt;b&gt;',
        ).blocks,
        [
          _paragraph(const [
            DefinitionSpan('&<>"\'\u00a0–—…«»© A😀\u{10ffff} &lt;b>'),
          ]),
        ],
      );
    });

    test('keeps unknown, invalid and incomplete references literal', () {
      const text =
          '&unknown; &#xD800; &#57343; &#x110000; &#1114112; '
          '&#-1; &#x; &amp &#65';
      expect(_convert('x', text).blocks, [
        _paragraph(const [DefinitionSpan(text)]),
      ]);
    });
  });

  group('ADR-0009 hostile markup', () {
    test('an unclosed script discards the rest of the field', () {
      expect(
        _convert(
          'h',
          'visible<ScRiPt src="external">hidden<b>still hidden',
        ).blocks,
        [
          _paragraph(const [DefinitionSpan('visible')]),
        ],
      );
    });

    test('recovers from mismatched closers and unclosed formatting', () {
      expect(_convert('h', '</p><b><i>both</b></i>plain<em>italic').blocks, [
        _paragraph(const [
          DefinitionSpan('both', bold: true, italic: true),
          DefinitionSpan('plain'),
          DefinitionSpan('italic', italic: true),
        ]),
      ]);
    });

    test('incomplete tags and repeated less-than signs stay literal', () {
      final text = '${'<abc' * 10000}<b title=">';
      expect(_convert('h', text).blocks, [
        _paragraph([DefinitionSpan(text)]),
      ]);
    });

    test('deep tags become literal and formatting resumes after them', () {
      final result = _convert(
        'h',
        '${'<b>' * 10000}deep<script>hidden</script>${'</b>' * 10000}tail',
      );
      final spans = result.blocks.single.spans;
      expect(spans.first.text, contains('<b>deep</b>'));
      expect(spans.first.text, isNot(contains('hidden')));
      expect(spans.first.bold, isTrue);
      expect(spans.last, const DefinitionSpan('tail'));
    });

    test('huge named and numeric references preserve invalid text', () {
      final invalid = '&${'a' * 100000}; &#${'9' * 100000};';
      expect(_convert('h', '$invalid &#x${'0' * 100000}41;').blocks, [
        _paragraph([DefinitionSpan('$invalid A')]),
      ]);
    });
  });
}
