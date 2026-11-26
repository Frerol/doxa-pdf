// SPDX-License-Identifier: GPL-3.0-or-later

enum DefinitionBlockKind { paragraph, listItem }

/// A run of text, or an explicit line break when [text] is null.
final class DefinitionSpan {
  const DefinitionSpan(
    String this.text, {
    this.bold = false,
    this.italic = false,
  });

  const DefinitionSpan.lineBreak() : text = null, bold = false, italic = false;

  final String? text;
  final bool bold;
  final bool italic;

  @override
  bool operator ==(Object other) =>
      other is DefinitionSpan &&
      text == other.text &&
      bold == other.bold &&
      italic == other.italic;

  @override
  int get hashCode => Object.hash(text, bold, italic);
}

final class DefinitionBlock {
  DefinitionBlock(this.kind, Iterable<DefinitionSpan> spans)
    : spans = List.unmodifiable(spans);

  final DefinitionBlockKind kind;
  final List<DefinitionSpan> spans;

  @override
  bool operator ==(Object other) =>
      other is DefinitionBlock &&
      kind == other.kind &&
      spans.length == other.spans.length &&
      spans.indexed.every((entry) => entry.$2 == other.spans[entry.$1]);

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(spans));
}

final class DefinitionResult {
  DefinitionResult(
    Iterable<DefinitionBlock> blocks, {
    required this.unsupportedFields,
  }) : blocks = List.unmodifiable(blocks);

  final List<DefinitionBlock> blocks;
  final int unsupportedFields;
}
