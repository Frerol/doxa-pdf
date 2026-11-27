// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_controller.dart';

/// Measures each pan, pinch or fling of the reader and logs one
/// `DOXA-PERF` line per interaction (read with `adb logcat -s flutter`),
/// so frame budgets (NFR-PERF-003) and memory (NFR-PERF-006) can be checked
/// on the reference tablet with a profile build.
/// `rssNoGpu` reads VmRSS and excludes graphics memory. Read GPU memory with
/// `adb shell dumpsys meminfo io.github.frerol.doxapdf` (GL mtrack + EGL mtrack).
final class FrameProbe {
  FrameProbe({this.budget = const Duration(microseconds: 11111)});

  /// Frame budget of the screen: 90 Hz on the reference tablet.
  final Duration budget;

  final _timings = <ui.FrameTiming>[];
  var _active = false;
  var _painted = 0;
  var _blank = 0;
  var _registered = false;
  Timer? _reportTimer;

  /// The last report, for tests.
  String? lastReport;

  void start() {
    _reportTimer?.cancel();
    if (!_registered) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _registered = true;
    }
    _timings.clear();
    _painted = 0;
    _blank = 0;
    _active = true;
  }

  void painted({required bool blank}) {
    if (!_active) return;
    _painted++;
    if (blank) _blank++;
  }

  /// Ends the interaction and logs its report once the last frames are in.
  void stop(ReaderController controller) {
    if (!_active) return;
    _active = false;
    _reportTimer = Timer(const Duration(milliseconds: 500), () {
      lastReport = report(controller);
      debugPrint(lastReport);
    });
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    if (_active) _timings.addAll(timings);
  }

  String report(ReaderController controller) {
    int worst(ui.FrameTiming t) => [
      t.buildDuration.inMicroseconds,
      t.rasterDuration.inMicroseconds,
    ].reduce((a, b) => a > b ? a : b);
    final times = [for (final t in _timings) worst(t)]..sort();
    int percentile(double p) =>
        times.isEmpty ? 0 : times[((times.length - 1) * p).round()];
    final overBudget = times.where((t) => t > budget.inMicroseconds).length;
    final over32 = times.where((t) => t > 32000).length;
    return 'DOXA-PERF frames=${times.length} '
        'over${(budget.inMicroseconds / 1000).toStringAsFixed(1)}ms=$overBudget '
        'over32ms=$over32 p50=${percentile(.5) / 1000}ms '
        'p95=${percentile(.95) / 1000}ms blankFrames=$_blank/$_painted '
        'zoom=${controller.zoom.toStringAsFixed(2)} '
        'cache=${controller.cache.bytes >> 20}MB/${controller.cache.length} '
        'rssNoGpu=${_rssMegabytes()}MB';
  }

  static int _rssMegabytes() {
    try {
      final line = File('/proc/self/status')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('VmRSS'));
      return int.parse(line.split(RegExp(r'\s+'))[1]) ~/ 1024;
    } on Object {
      return -1;
    }
  }

  void dispose() {
    _reportTimer?.cancel();
    _active = false;
    if (_registered) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    }
  }
}
