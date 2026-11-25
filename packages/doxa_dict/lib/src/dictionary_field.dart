// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'dictionary_format_exception.dart';

/// A StarDict field with its framing removed.
final class DictionaryField {
  DictionaryField._(this.type, Uint8List bytes, this.text)
    : bytes = bytes.asUnmodifiableView();

  final String type;
  final Uint8List bytes;

  /// Strictly decoded UTF-8 for a lowercase type, or null for binary data.
  final String? text;

  /// Parses one entry using the optional .ifo sameTypeSequence.
  static List<DictionaryField> parse(
    Uint8List entry, {
    String? sameTypeSequence,
  }) {
    if (sameTypeSequence == '') {
      throw const DictionaryFormatException('Empty sametypesequence');
    }
    final fields = <DictionaryField>[];
    final data = ByteData.sublistView(entry);
    var position = 0;
    var fieldIndex = 0;
    while (sameTypeSequence == null
        ? position < entry.length
        : fieldIndex < sameTypeSequence.length) {
      final type = sameTypeSequence == null
          ? entry[position++]
          : sameTypeSequence.codeUnitAt(fieldIndex);
      fieldIndex++;
      final isText = type >= 0x61 && type <= 0x7a;
      if (!isText && (type < 0x41 || type > 0x5a)) {
        throw const DictionaryFormatException('Invalid dictionary field type');
      }

      final int end;
      var terminatorLength = 0;
      if (fieldIndex == sameTypeSequence?.length) {
        end = entry.length;
      } else if (isText) {
        end = entry.indexOf(0, position);
        if (end < 0) {
          throw const DictionaryFormatException('Unterminated text field');
        }
        terminatorLength = 1;
      } else {
        if (entry.length - position < 4) {
          throw const DictionaryFormatException(
            'Truncated binary field length',
          );
        }
        final size = data.getUint32(position);
        position += 4;
        if (size > entry.length - position) {
          throw const DictionaryFormatException('Truncated binary field');
        }
        end = position + size;
      }

      final bytes = entry.sublist(position, end);
      String? text;
      if (isText) {
        try {
          text = utf8.decode(bytes);
        } on FormatException {
          throw const DictionaryFormatException('Invalid UTF-8 in text field');
        }
      }
      fields.add(DictionaryField._(String.fromCharCode(type), bytes, text));
      position = end + terminatorLength;
    }
    return List.unmodifiable(fields);
  }
}
