// SPDX-License-Identifier: GPL-3.0-or-later
import 'annotation.dart';
import 'geometry.dart';

/// JSON for [Annotation]s, so commands that carry them can be stored in
/// the crash journal (`docs/plan/03-architecture.md` §5).
///
/// The output holds only JSON values (maps, lists, strings, numbers, bools
/// and null). Points, quads and rects are flat number lists to keep ink
/// small. Decoding throws a [FormatException] on anything it does not
/// understand, so a damaged journal entry is never applied half-read.
abstract final class AnnotationJson {
  static Map<String, Object?> encode(Annotation annotation) => {
    'id': annotation.id,
    'page': annotation.pageIndex,
    'subtype': annotation.subtype,
    'rect': _rect(annotation.rect),
    if (annotation.color != null) 'color': annotation.color,
    'opacity': annotation.opacity,
    if (annotation.author != null) 'author': annotation.author,
    if (annotation.contents != null) 'contents': annotation.contents,
    if (annotation.modified != null)
      'modified': annotation.modified!.toIso8601String(),
    'flags': annotation.flags,
    'byDoxa': annotation.byDoxa,
    ...switch (annotation) {
      TextMarkup(:final quads, :final text) => {
        'quads': [for (final q in quads) ...q.toList()],
        'text': ?text,
      },
      InkAnnotation(:final strokes, :final width, :final tool) => {
        'width': width,
        'tool': tool.name,
        'strokes': [
          for (final s in strokes)
            {
              'points': [
                for (final p in s.points) ...[p.x, p.y],
              ],
              if (s.pressures != null) 'pressures': s.pressures,
            },
        ],
      },
      OtherAnnotation() => const {},
    },
  };

  static Annotation decode(Object? json) {
    final map = _map(json, 'annotation');
    final id = _field<String>(map, 'id');
    final pageIndex = _field<int>(map, 'page');
    final subtype = _field<String>(map, 'subtype');
    final rect = _toRect(_field<List<Object?>>(map, 'rect'));
    final color = _optional<int>(map, 'color');
    final opacity = _number(map['opacity'], 'opacity');
    final author = _optional<String>(map, 'author');
    final contents = _optional<String>(map, 'contents');
    final modifiedText = _optional<String>(map, 'modified');
    final modified = modifiedText == null
        ? null
        : DateTime.tryParse(modifiedText) ??
              (throw FormatException('Bad date', modifiedText));
    final flags = _field<int>(map, 'flags');
    final byDoxa = _field<bool>(map, 'byDoxa');

    if (subtype == 'Ink') {
      final toolName = _field<String>(map, 'tool');
      final tool = InkTool.values.firstWhere(
        (t) => t.name == toolName,
        orElse: () => throw FormatException('Unknown ink tool', toolName),
      );
      final strokes = [
        for (final s in _field<List<Object?>>(map, 'strokes'))
          _toStroke(_map(s, 'stroke')),
      ];
      if (strokes.isEmpty) throw const FormatException('Ink without strokes');
      final width = _number(map['width'], 'width');
      if (!(width > 0)) throw FormatException('Bad ink width', width);
      return InkAnnotation(
        id: id,
        pageIndex: pageIndex,
        rect: rect,
        strokes: strokes,
        width: width,
        tool: tool,
        color: color,
        opacity: opacity,
        author: author,
        contents: contents,
        modified: modified,
        flags: flags,
        byDoxa: byDoxa,
      );
    }
    final kind = MarkupKind.fromSubtype(subtype);
    if (kind != null) {
      final numbers = _numbers(_field<List<Object?>>(map, 'quads'), 'quads');
      if (numbers.isEmpty || numbers.length % 8 != 0) {
        throw const FormatException('Quads need 8 numbers each');
      }
      return TextMarkup(
        id: id,
        pageIndex: pageIndex,
        rect: rect,
        kind: kind,
        quads: [
          for (var i = 0; i < numbers.length; i += 8)
            PdfQuad(
              PdfPoint(numbers[i], numbers[i + 1]),
              PdfPoint(numbers[i + 2], numbers[i + 3]),
              PdfPoint(numbers[i + 4], numbers[i + 5]),
              PdfPoint(numbers[i + 6], numbers[i + 7]),
            ),
        ],
        text: _optional<String>(map, 'text'),
        color: color,
        opacity: opacity,
        author: author,
        contents: contents,
        modified: modified,
        flags: flags,
        byDoxa: byDoxa,
      );
    }
    return OtherAnnotation(
      id: id,
      pageIndex: pageIndex,
      rect: rect,
      subtype: subtype,
      color: color,
      opacity: opacity,
      author: author,
      contents: contents,
      modified: modified,
      flags: flags,
      byDoxa: byDoxa,
    );
  }

  static List<double> _rect(PdfRect r) => [r.left, r.bottom, r.right, r.top];

  static PdfRect _toRect(List<Object?> list) {
    final n = _numbers(list, 'rect');
    if (n.length != 4) throw FormatException('A rect has 4 numbers', list);
    return PdfRect(n[0], n[1], n[2], n[3]);
  }

  static InkStroke _toStroke(Map<String, Object?> map) {
    final n = _numbers(_field<List<Object?>>(map, 'points'), 'points');
    if (n.isEmpty || n.length.isOdd) {
      throw const FormatException('A stroke needs x, y pairs');
    }
    final points = [
      for (var i = 0; i < n.length; i += 2) PdfPoint(n[i], n[i + 1]),
    ];
    final rawPressures = _optional<List<Object?>>(map, 'pressures');
    final pressures = rawPressures == null
        ? null
        : _numbers(rawPressures, 'pressures');
    if (pressures != null && pressures.length != points.length) {
      throw const FormatException('One pressure per point');
    }
    return InkStroke(points, pressures: pressures);
  }
}

Map<String, Object?> _map(Object? json, String what) => json is Map
    ? json.cast<String, Object?>()
    : throw FormatException('Expected a JSON object for $what', json);

T _field<T>(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is T) return value;
  throw FormatException('Missing or bad "$key"', map);
}

T? _optional<T>(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null || value is T) return value as T?;
  throw FormatException('Bad "$key"', map);
}

double _number(Object? value, String what) => value is num
    ? value.toDouble()
    : throw FormatException('Expected a number for $what', value);

List<double> _numbers(List<Object?> list, String what) => [
  for (final v in list) _number(v, what),
];

/// Helpers for the command JSON in `annotation_command.dart`.
Map<String, Object?> jsonMap(Object? json, String what) => _map(json, what);
T jsonField<T>(Map<String, Object?> map, String key) => _field<T>(map, key);
double jsonNumber(Object? value, String what) => _number(value, what);
