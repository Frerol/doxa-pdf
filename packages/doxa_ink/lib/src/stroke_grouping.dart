// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_core/doxa_core.dart';

/// The properties shared by all strokes in one Ink annotation (FR-INK-011).
/// Width is the configured width in PDF points at full pressure.
typedef StrokeGroupKey = ({
  int pageIndex,
  InkTool tool,
  int? color,
  double width,
  double opacity,
});

enum StrokeGroupDecision { startNew, append }

/// Decides which finished strokes can share one Ink annotation (FR-INK-011).
/// Keep one instance per document and call [reset] when the current group is
/// no longer available for appending (for example after undo).
final class StrokeGrouper {
  StrokeGrouper({this.window = defaultWindow}) {
    if (window.isNegative) throw ArgumentError.value(window, 'window');
  }

  static const defaultWindow = Duration(milliseconds: 1500);

  /// Maximum idle gap between strokes, inclusive.
  final Duration window;

  StrokeGroupKey? _previousKey;
  Duration? _previousEnd;

  /// Records a finished stroke. Supply pen-down and pen-up times from the same
  /// monotonic time source. The gap is measured from the previous pen-up to
  /// this pen-down. A negative gap starts a new group. A different key starts
  /// a new group even at a zero gap.
  StrokeGroupDecision addStroke({
    required StrokeGroupKey key,
    required Duration start,
    required Duration end,
  }) {
    if (end < start) throw ArgumentError.value(end, 'end', 'Precedes start');
    final previousEnd = _previousEnd;
    final gap = previousEnd == null ? null : start - previousEnd;
    final append =
        key == _previousKey && gap != null && !gap.isNegative && gap <= window;
    _previousKey = key;
    _previousEnd = end;
    return append ? StrokeGroupDecision.append : StrokeGroupDecision.startNew;
  }

  void reset() {
    _previousKey = null;
    _previousEnd = null;
  }
}
