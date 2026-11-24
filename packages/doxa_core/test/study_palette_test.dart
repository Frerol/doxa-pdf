// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'package:doxa_core/doxa_core.dart';
import 'package:test/test.dart';

void main() {
  test('T-05 FR-MARK-002 default colors and order', () {
    expect(StudyPalette.defaults().colors.map((c) => c.argb), [
      0xFFFFEB3B,
      0xFFA5D6A7,
      0xFF90CAF9,
      0xFFF48FB1,
      0xFFFFCC80,
      0xFFCE93D8,
    ]);
    expect(
      StudyPalette.defaults().colors.every((c) => c.label == null),
      isTrue,
    );
  });
  test('T-05 FR-MARK-011 relabel and clear label', () {
    final palette = StudyPalette.defaults();
    palette.relabel(0, 'Key concepts');
    expect(
      palette.colors.first,
      const StudyColor(0xFFFFEB3B, label: 'Key concepts'),
    );
    palette.relabel(0, null);
    expect(palette.colors.first.label, isNull);
    expect(StudyPalette.defaults().colors.first.label, isNull);
  });
  test('T-05 moves in both directions and to the same index', () {
    final palette = StudyPalette([
      const StudyColor(1),
      const StudyColor(2),
      const StudyColor(3),
    ]);
    palette.move(0, 2);
    expect(palette.colors.map((c) => c.argb), [2, 3, 1]);
    palette.move(2, 0);
    palette.move(1, 1);
    expect(palette.colors.map((c) => c.argb), [1, 2, 3]);
  });
  test('T-05 FR-MARK-011 JSON round trip and unknown fields', () {
    final palette = StudyPalette.defaults()..relabel(1, 'Review');
    final json =
        jsonDecode(jsonEncode(palette.toJson())) as Map<String, Object?>;
    json['future'] = true;
    final first =
        (json['colors'] as List<Object?>).first as Map<String, Object?>;
    first['future'] = 'ignored';
    expect(StudyPalette.fromJson(json).colors, palette.colors);
    expect(StudyPalette.fromJson({'colors': <Object?>[]}).colors, isEmpty);
  });
  test('T-05 bounds errors leave palette unchanged', () {
    final palette = StudyPalette.defaults();
    final before = palette.colors;
    for (final index in [-1, 6]) {
      expect(() => palette.relabel(index, 'x'), throwsRangeError);
      expect(() => palette.move(index, 0), throwsRangeError);
      expect(() => palette.move(0, index), throwsRangeError);
    }
    expect(palette.colors, before);
    expect(() => StudyPalette([]).move(0, 0), throwsRangeError);
  });
  test('T-05 maximum size enforced for construction and JSON', () {
    final colors = List.filled(12, const StudyColor(1), growable: true);
    expect(StudyPalette(colors).colors, hasLength(12));
    colors.add(const StudyColor(2));
    expect(() => StudyPalette(colors), throwsArgumentError);
    expect(
      () => StudyPalette.fromJson({
        'colors': colors.map((c) => c.toJson()).toList(),
      }),
      throwsArgumentError,
    );
  });
  test('T-05 input and exposed lists cannot mutate palette', () {
    final input = [const StudyColor(1)];
    final palette = StudyPalette(input);
    input.clear();
    expect(palette.colors, hasLength(1));
    expect(() => palette.colors.clear(), throwsUnsupportedError);
  });
  test('T-05 malformed JSON is rejected', () {
    for (final json in <Map<String, Object?>>[
      {},
      {'colors': 1},
      {
        'colors': [1],
      },
      {
        'colors': [
          {'argb': 'bad'},
        ],
      },
      {
        'colors': [
          {'argb': -1},
        ],
      },
      {
        'colors': [
          {'argb': 0x100000000},
        ],
      },
      {
        'colors': [
          {'argb': 1, 'label': 2},
        ],
      },
    ]) {
      expect(() => StudyPalette.fromJson(json), throwsFormatException);
    }
  });
}
