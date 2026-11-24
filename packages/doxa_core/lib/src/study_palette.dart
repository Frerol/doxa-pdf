// SPDX-License-Identifier: GPL-3.0-or-later

/// A study markup color, with an optional user-defined label.
final class StudyColor {
  const StudyColor(this.argb, {this.label});
  final int argb;
  final String? label;

  Map<String, Object?> toJson() => {'argb': argb, 'label': label};

  factory StudyColor.fromJson(Map<String, Object?> json) {
    final argb = json['argb'];
    final label = json['label'];
    if (argb is! int ||
        argb < 0 ||
        argb > 0xffffffff ||
        (label != null && label is! String)) {
      throw const FormatException('Invalid study color');
    }
    return StudyColor(argb, label: label as String?);
  }

  @override
  bool operator ==(Object other) =>
      other is StudyColor && argb == other.argb && label == other.label;
  @override
  int get hashCode => Object.hash(argb, label);
}

/// An ordered, editable palette for FR-MARK-002 and FR-MARK-011.
final class StudyPalette {
  StudyPalette(Iterable<StudyColor> colors) : _colors = List.of(colors) {
    if (_colors.length > maxSize) {
      throw ArgumentError.value(_colors.length, 'colors', 'At most 12 colors');
    }
  }

  static const int maxSize = 12;
  final List<StudyColor> _colors;

  /// An unmodifiable snapshot of the current order.
  List<StudyColor> get colors => List.unmodifiable(_colors);

  factory StudyPalette.defaults() => StudyPalette(const [
    StudyColor(0xFFFFEB3B),
    StudyColor(0xFFA5D6A7),
    StudyColor(0xFF90CAF9),
    StudyColor(0xFFF48FB1),
    StudyColor(0xFFFFCC80),
    StudyColor(0xFFCE93D8),
  ]);

  void relabel(int index, String? label) {
    final color = _colors[index];
    _colors[index] = StudyColor(color.argb, label: label);
  }

  /// Moves a color to its final index, preserving the other colors' order.
  void move(int from, int to) {
    RangeError.checkValidIndex(from, _colors, 'from');
    RangeError.checkValidIndex(to, _colors, 'to');
    final color = _colors.removeAt(from);
    _colors.insert(to, color);
  }

  Map<String, Object?> toJson() => {
    'colors': _colors.map((color) => color.toJson()).toList(),
  };

  /// Unknown fields are ignored; malformed known fields are rejected.
  factory StudyPalette.fromJson(Map<String, Object?> json) {
    final entries = json['colors'];
    if (entries is! List<Object?>) {
      throw const FormatException('Expected a colors list');
    }
    return StudyPalette(
      entries.map((entry) {
        if (entry is! Map<String, Object?>) {
          throw const FormatException('Expected a study color object');
        }
        return StudyColor.fromJson(entry);
      }),
    );
  }
}
