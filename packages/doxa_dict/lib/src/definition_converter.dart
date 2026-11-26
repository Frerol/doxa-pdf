// SPDX-License-Identifier: GPL-3.0-or-later

import 'definition.dart';
import 'dictionary_field.dart';

/// Reduces the framed StarDict fields to inert text for display (ADR-0009).
DefinitionResult convertDefinition(Iterable<DictionaryField> fields) {
  final blocks = <DefinitionBlock>[];
  var unsupportedFields = 0;
  for (final field in fields) {
    final source = field.text;
    final type = field.type;
    if (source == null ||
        !const {'m', 't', 'y', 'g', 'h', 'x'}.contains(type)) {
      unsupportedFields++;
      continue;
    }
    _DefinitionScanner(source, type, blocks).scan();
  }
  return DefinitionResult(blocks, unsupportedFields: unsupportedFields);
}

const _maxDepth = 64;

enum _Effect { none, paragraph, listItem, list, bold, italic, heading }

final class _DefinitionScanner {
  _DefinitionScanner(this.source, this.type, this.blocks);

  final String source;
  final String type;
  final List<DefinitionBlock> blocks;
  final _stack = <(String, _Effect, DefinitionBlockKind)>[];
  final _run = StringBuffer();
  final _spans = <DefinitionSpan>[];
  var _kind = DefinitionBlockKind.paragraph;
  var _bold = 0;
  var _italic = 0;
  var _overflow = 0;
  var _position = 0;
  String? _discard;

  bool get _plain => type == 'm' || type == 't' || type == 'y';

  void scan() {
    while (_position < source.length) {
      if (_discard case final name?) {
        // Raw bodies only recognize their own end tag. Quotes and other
        // apparent tags in the body cannot hide that closing delimiter.
        final start = source.indexOf('<', _position);
        if (start < 0) break;
        _position = start + 1;
        final nameEnd = start + 2 + name.length;
        if (nameEnd < source.length &&
            source.startsWith('</', start) &&
            source.substring(start + 2, nameEnd).toLowerCase() == name &&
            (_isSpace(source.codeUnitAt(nameEnd)) ||
                source.codeUnitAt(nameEnd) == 0x3e ||
                source.codeUnitAt(nameEnd) == 0x2f)) {
          final (end, complete) = _tagEnd(nameEnd);
          _position = end;
          if (complete) _discard = null;
        }
        continue;
      }

      final start = _position;
      switch (source.codeUnitAt(start)) {
        case 0x3c when !_plain:
          _scanTag();
        case 0x26 when !_plain:
          _scanEntity();
        case 0x0a || 0x0d:
          _position++;
          if (source.codeUnitAt(start) == 0x0d &&
              _position < source.length &&
              source.codeUnitAt(_position) == 0x0a) {
            _position++;
          }
          _lineBreak();
        default:
          _position++;
          while (_position < source.length) {
            final unit = source.codeUnitAt(_position);
            if (unit == 0x0a ||
                unit == 0x0d ||
                (!_plain && (unit == 0x3c || unit == 0x26))) {
              break;
            }
            _position++;
          }
          _run.write(source.substring(start, _position));
      }
    }
    _finishBlock();
  }

  void _scanTag() {
    final start = _position++;
    if (source.startsWith('<!--', start)) {
      final end = source.indexOf('-->', start + 4);
      _position = end < 0 ? source.length : end + 3;
      return;
    }

    final closing = source.startsWith('/', _position);
    final nameStart = closing ? _position + 1 : _position;
    if (nameStart >= source.length ||
        !_isLetter(source.codeUnitAt(nameStart))) {
      _run.write('<');
      return;
    }

    var nameEnd = nameStart + 1;
    while (nameEnd < source.length && _isNameChar(source.codeUnitAt(nameEnd))) {
      nameEnd++;
    }
    final (end, complete) = _tagEnd(nameEnd);
    _position = end;
    if (!complete) {
      _run.write(source.substring(start, end));
      return;
    }

    final name = source.substring(nameStart, nameEnd).toLowerCase();
    final selfClosing = source.codeUnitAt(end - 2) == 0x2f;
    if (name == 'script' || name == 'style') {
      // HTML treats raw-text elements as open even with a trailing slash.
      if (!closing && (type == 'h' || !selfClosing)) _discard = name;
      return;
    }

    final isBreak = type == 'h' && name == 'br';
    final isVoid =
        type == 'h' &&
        const {
          'area',
          'base',
          'br',
          'col',
          'embed',
          'hr',
          'img',
          'input',
          'link',
          'meta',
          'param',
          'source',
          'track',
          'wbr',
        }.contains(name);

    if (_overflow > 0 || (!closing && _stack.length == _maxDepth)) {
      // Keep only a depth counter beyond the cap. Matching names there
      // would require an unbounded stack on hostile input.
      // Display the tag name literally, without retaining attributes.
      _run.write(source.substring(start, nameEnd));
      _run.write(selfClosing ? '/>' : '>');
      if (!isVoid) {
        if (closing) {
          _overflow--;
        } else if (!selfClosing) {
          _overflow++;
        }
      }
      return;
    }

    if (closing) {
      _close(name);
    } else if (isBreak) {
      _lineBreak();
    } else if (!isVoid) {
      final effect = _effect(name);
      final previousKind = _kind;
      _enter(effect);
      if (selfClosing) {
        _leave(effect);
        _kind = previousKind;
      } else {
        _stack.add((name, effect, previousKind));
      }
    }
  }

  // Stops at the next unquoted delimiter without rescanning malformed tags.
  (int, bool) _tagEnd(int position) {
    var quote = 0;
    while (position < source.length) {
      final unit = source.codeUnitAt(position);
      if (quote != 0) {
        if (unit == quote) quote = 0;
      } else if (unit == 0x22 || unit == 0x27) {
        quote = unit;
      } else if (unit == 0x3e) {
        return (position + 1, true);
      } else if (unit == 0x3c) {
        break;
      }
      position++;
    }
    return (position, false);
  }

  _Effect _effect(String name) => switch ((type, name)) {
    ('h', 'p') || ('x', 'blockquote') => _Effect.paragraph,
    ('h', 'li') => _Effect.listItem,
    ('h', 'ul' || 'ol') => _Effect.list,
    ('h', 'b' || 'strong') || ('x', 'b') => _Effect.bold,
    ('h', 'i' || 'em') || ('x', 'i' || 'ex' || 'abr') => _Effect.italic,
    ('x', 'k') => _Effect.heading,
    _ => _Effect.none,
  };

  void _enter(_Effect effect) {
    switch (effect) {
      case _Effect.paragraph || _Effect.list:
        _finishBlock();
        _kind = DefinitionBlockKind.paragraph;
      case _Effect.listItem:
        _finishBlock();
        _kind = DefinitionBlockKind.listItem;
      case _Effect.heading:
        _finishBlock();
        _kind = DefinitionBlockKind.paragraph;
        _bold++;
      case _Effect.bold:
        _flushRun();
        _bold++;
      case _Effect.italic:
        _flushRun();
        _italic++;
      case _Effect.none:
        break;
    }
  }

  void _close(String name) {
    final index = _stack.lastIndexWhere((entry) => entry.$1 == name);
    if (index < 0) return;
    while (_stack.length > index) {
      final (_, effect, previousKind) = _stack.removeLast();
      _leave(effect);
      _kind = previousKind;
    }
  }

  void _leave(_Effect effect) {
    switch (effect) {
      case _Effect.paragraph || _Effect.listItem || _Effect.list:
        _finishBlock();
      case _Effect.heading:
        _finishBlock();
        _bold--;
      case _Effect.bold:
        _flushRun();
        _bold--;
      case _Effect.italic:
        _flushRun();
        _italic--;
      case _Effect.none:
        break;
    }
  }

  void _flushRun() {
    if (_run.isEmpty) return;
    _spans.add(
      DefinitionSpan(_run.toString(), bold: _bold > 0, italic: _italic > 0),
    );
    _run.clear();
  }

  void _lineBreak() {
    _flushRun();
    _spans.add(const DefinitionSpan.lineBreak());
  }

  void _finishBlock() {
    _flushRun();
    if (_spans.isNotEmpty) {
      blocks.add(DefinitionBlock(_kind, _spans));
      _spans.clear();
    }
  }

  void _scanEntity() {
    final start = _position++;
    final body = _position;
    final numeric = source.startsWith('#', body);
    String? decoded;
    if (numeric) {
      _position++;
      final hex =
          source.startsWith('x', _position) ||
          source.startsWith('X', _position);
      if (hex) _position++;
      final digits = _position;
      final radix = hex ? 16 : 10;
      var value = 0;
      while (_position < source.length) {
        final digit = _hexDigit(source.codeUnitAt(_position));
        if (digit < 0 || digit >= radix) break;
        // Saturate out of range, but consume all digits (including leading zeroes).
        if (value <= 0x10ffff) value = value * radix + digit;
        _position++;
      }
      if (_position > digits &&
          value <= 0x10ffff &&
          !(value >= 0xd800 && value <= 0xdfff)) {
        decoded = String.fromCharCode(value);
      }
    } else {
      while (_position < source.length &&
          _isLetter(source.codeUnitAt(_position))) {
        _position++;
      }
      if (_position - body <= 6) {
        decoded = _entities[source.substring(body, _position)];
      }
    }
    if (source.startsWith(';', _position)) {
      _position++;
    } else {
      decoded = null;
    }
    _run.write(decoded ?? source.substring(start, _position));
  }
}

const _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': '\u00a0',
  'ndash': '–',
  'mdash': '—',
  'hellip': '…',
  'laquo': '«',
  'raquo': '»',
  'copy': '©',
};

bool _isSpace(int unit) => unit == 0x20 || (unit >= 0x09 && unit <= 0x0d);

bool _isLetter(int unit) => (unit | 0x20) >= 0x61 && (unit | 0x20) <= 0x7a;

bool _isNameChar(int unit) =>
    _isLetter(unit) ||
    (unit >= 0x30 && unit <= 0x39) ||
    unit == 0x2d ||
    unit == 0x3a ||
    unit == 0x5f ||
    unit == 0x2e;

int _hexDigit(int unit) {
  if (unit >= 0x30 && unit <= 0x39) return unit - 0x30;
  final lower = unit | 0x20;
  return lower >= 0x61 && lower <= 0x66 ? lower - 0x61 + 10 : -1;
}
