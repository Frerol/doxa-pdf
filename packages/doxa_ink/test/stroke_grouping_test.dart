// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_ink/doxa_ink.dart';
import 'package:test/test.dart';

const StrokeGroupKey _style = (
  pageIndex: 0,
  tool: InkTool.pen,
  color: 0x102030,
  width: 2,
  opacity: 1,
);

void main() {
  group('FR-INK-011 stroke grouping', () {
    test('the inclusive window rolls forward from each pen-up', () {
      final grouper = StrokeGrouper();
      final window = grouper.window;
      var end = Duration.zero;

      StrokeGroupDecision addAfter(Duration gap) {
        final start = end + gap;
        end = start + window * 2;
        return grouper.addStroke(key: _style, start: start, end: end);
      }

      const tick = Duration(microseconds: 1);
      expect(addAfter(Duration.zero), StrokeGroupDecision.startNew);
      expect(addAfter(window - tick), StrokeGroupDecision.append);
      expect(addAfter(window), StrokeGroupDecision.append);
      expect(addAfter(window + tick), StrokeGroupDecision.startNew);
      expect(addAfter(Duration.zero), StrokeGroupDecision.append);
    });

    final changes = <String, StrokeGroupKey>{
      'page': (
        pageIndex: 1,
        tool: _style.tool,
        color: _style.color,
        width: _style.width,
        opacity: _style.opacity,
      ),
      'tool': (
        pageIndex: _style.pageIndex,
        tool: InkTool.highlighter,
        color: _style.color,
        width: _style.width,
        opacity: _style.opacity,
      ),
      'color': (
        pageIndex: _style.pageIndex,
        tool: _style.tool,
        color: null,
        width: _style.width,
        opacity: _style.opacity,
      ),
      'width': (
        pageIndex: _style.pageIndex,
        tool: _style.tool,
        color: _style.color,
        width: 3,
        opacity: _style.opacity,
      ),
      'opacity': (
        pageIndex: _style.pageIndex,
        tool: _style.tool,
        color: _style.color,
        width: _style.width,
        opacity: 0.5,
      ),
    };
    for (final change in changes.entries) {
      test('changing ${change.key} breaks the group at any gap', () {
        final grouper = StrokeGrouper();
        var time = Duration.zero;
        StrokeGroupDecision add(StrokeGroupKey key) {
          final start = time;
          time += const Duration(milliseconds: 10);
          return grouper.addStroke(key: key, start: start, end: time);
        }

        add(_style);
        expect(add(change.value), StrokeGroupDecision.startNew);
        expect(add(change.value), StrokeGroupDecision.append);
        expect(add(_style), StrokeGroupDecision.startNew);
      });
    }

    test('overlapping timestamps and a reset start new groups', () {
      final grouper = StrokeGrouper(window: Duration.zero);
      const start = Duration(milliseconds: 5);
      const end = Duration(milliseconds: 10);
      grouper.addStroke(key: _style, start: start, end: end);
      expect(
        grouper.addStroke(key: _style, start: start, end: end),
        StrokeGroupDecision.startNew,
      );
      grouper.reset();
      expect(
        grouper.addStroke(key: _style, start: end, end: end),
        StrokeGroupDecision.startNew,
      );
    });
  });
}
