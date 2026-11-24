// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ink Lab — throwaway prototype for Spike B (issue #6).
// Measures what the S Pen delivers to Flutter and how long it takes for a
// stroke to reach the screen. Not product code; see docs/spikes/B-ink.md.

import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

void main() => runApp(const InkLabApp());

class InkLabApp extends StatelessWidget {
  const InkLabApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const InkLabPage(),
  );
}

// ---------------------------------------------------------------------------
// Model

class InkPoint {
  const InkPoint(this.pos, this.pressure, this.tUs);
  final Offset pos; // canvas coordinates
  final double pressure; // normalized 0..1
  final int tUs; // event timestamp, µs
}

class Stroke {
  Stroke(this.id, this.color, this.baseWidth, {required this.highlighter});
  final int id;
  final Color color;
  final double baseWidth;
  final bool highlighter;
  final List<InkPoint> points = [];
  final List<InkPoint> raw = []; // unsmoothed input, canvas coordinates
}

class LabSettings {
  bool pressure = true;
  bool smoothing = true; // unused since v3, kept for log compatibility
  /// 0 off, 1 One-Euro, 2.. arc-length smoothing with radius [arcRadii].
  int smoothMode = 3;
  static const arcRadii = [0.0, 0.0, 2.0, 4.0, 8.0];
  String get smoothLabel => switch (smoothMode) {
    0 => 'off',
    1 => '1€',
    _ => 'arc ${arcRadii[smoothMode].toStringAsFixed(0)}px',
  };
  bool prediction = false;
  bool stylusOnly = true;
  bool naiveRepaint = false;
  bool highlighter = false;
  bool outline = true; // filled variable-width outline instead of segments
  bool bake = true; // committed strokes cached as an image
}

// ---------------------------------------------------------------------------
// One-Euro filter (Casiez et al. 2012), per axis.

class _LowPass {
  double? _y;
  double filter(double x, double alpha) =>
      _y = _y == null ? x : alpha * x + (1 - alpha) * _y!;
  double? get last => _y;
}

class OneEuro {
  OneEuro({this.minCutoff = 1.0, this.beta = 0.02, this.dCutoff = 1.0});
  final double minCutoff, beta, dCutoff;
  final _x = _LowPass(), _dx = _LowPass();
  int? _lastUs;

  static double _alpha(double cutoff, double dt) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / dt);
  }

  double filter(double x, int tUs) {
    final last = _lastUs;
    _lastUs = tUs;
    if (last == null || tUs <= last) return _x.filter(x, 1);
    final dt = (tUs - last) / 1e6;
    final dx = (x - (_x.last ?? x)) / dt;
    final edx = _dx.filter(dx, _alpha(dCutoff, dt));
    final cutoff = minCutoff + beta * edx.abs();
    return _x.filter(x, _alpha(cutoff, dt));
  }
}

// ---------------------------------------------------------------------------
// Measurements

class _Sample {
  _Sample(this.strokeId, this.paintUs, this.eventUs);
  final int strokeId, paintUs, eventUs;
}

class StrokeStats {
  StrokeStats(this.id, this.kind);
  final int id;
  final PointerDeviceKind kind;
  int events = 0;
  int firstUs = 0, lastUs = 0;
  double minP = 1, maxP = 0;
  double minTilt = double.infinity, maxTilt = -double.infinity;
  final Set<int> buttons = {};
  final List<int> dartDelayUs = []; // event timestamp -> Dart handler
  final List<int> rasterUs = []; // event timestamp -> raster finished
  final List<int> intervalsUs = [];
  final List<Offset> raw = []; // logical px as received, before filtering
  String? firstEvent;
}

int _pct(List<int> v, double p) {
  if (v.isEmpty) return -1;
  final s = [...v]..sort();
  return s[((s.length - 1) * p).round()];
}

String _ms(int us) => us < 0 ? '—' : (us / 1000).toStringAsFixed(1);

// ---------------------------------------------------------------------------
// Page

class InkLabPage extends StatefulWidget {
  const InkLabPage({super.key});

  @override
  State<InkLabPage> createState() => _InkLabPageState();
}

class _InkLabPageState extends State<InkLabPage> {
  final settings = LabSettings();
  final strokes = <Stroke>[];
  final committedVersion = ValueNotifier<int>(0);
  final live = ValueNotifier<int>(0); // bumps on every live change
  final view = ValueNotifier<int>(0); // bumps when the transform changes
  final hud = ValueNotifier<String>('Write with the S Pen.');

  Matrix4 transform = Matrix4.identity();
  Stroke? current;
  StrokeStats? stats;
  Offset? hover;
  Offset? predicted;
  int lastStylusSeenUs = 0;
  int rejectedTouches = 0;
  int strokeCounter = 0;
  int? activePointer;
  OneEuro? fx, fy;

  final _pending = <_Sample>[];
  final _done = <StrokeStats>[];
  Timer? _hudTimer;

  static const palette = [Colors.black, Color(0xFF1565C0), Color(0xFFC62828)];
  int colorIndex = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _hudTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _refreshHud(),
    );
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _hudTimer?.cancel();
    super.dispose();
  }

  int get _nowUs => Timeline.now;

  // Input ------------------------------------------------------------------

  bool _isPen(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus;

  bool _draws(PointerEvent e) =>
      _isPen(e) ||
      (!settings.stylusOnly &&
          (e.kind == PointerDeviceKind.touch ||
              e.kind == PointerDeviceKind.mouse));

  bool _erases(PointerEvent e) =>
      e.kind == PointerDeviceKind.invertedStylus ||
      (e.buttons & (kPrimaryStylusButton | kSecondaryStylusButton)) != 0;

  /// Touches are ignored while the pen is down or hovered recently.
  bool get penNearby =>
      activePointer != null || _nowUs - lastStylusSeenUs < 300000;

  Offset _toCanvas(Offset p) =>
      MatrixUtils.transformPoint(Matrix4.inverted(transform), p);

  double _normPressure(PointerEvent e) {
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _onDown(PointerDownEvent e) {
    if (_isPen(e)) lastStylusSeenUs = _nowUs;
    if (!_draws(e) || activePointer != null) return;
    activePointer = e.pointer;
    final s = StrokeStats(++strokeCounter, e.kind)
      ..firstEvent =
          'kind=${e.kind.name} pressure=${e.pressure.toStringAsFixed(3)} '
          '[${e.pressureMin}..${e.pressureMax}] tilt=${e.tilt.toStringAsFixed(2)} '
          'orientation=${e.orientation.toStringAsFixed(2)} buttons=${e.buttons} '
          'distanceMax=${e.distanceMax} radiusMajor=${e.radiusMajor.toStringAsFixed(1)}';
    stats = s;
    if (_erases(e)) {
      _startInteraction('erase');
      _eraseAt(_toCanvas(e.localPosition));
    } else {
      current = Stroke(
        s.id,
        palette[colorIndex],
        settings.highlighter ? 18 : 3.2,
        highlighter: settings.highlighter,
      );
      fx = OneEuro();
      fy = OneEuro();
    }
    _record(e);
  }

  void _onMove(PointerMoveEvent e) {
    if (_isPen(e)) lastStylusSeenUs = _nowUs;
    if (e.pointer != activePointer) return;
    _record(e);
  }

  void _onUp(PointerEvent e) {
    if (_isPen(e)) lastStylusSeenUs = _nowUs;
    if (e.pointer != activePointer) return;
    activePointer = null;
    predicted = null;
    final c = current;
    if (c != null && c.points.isNotEmpty) {
      strokes.add(c);
      _bakeAppend(c);
    }
    current = null;
    live.value++;
    if (interaction == 'erase') _endInteraction();
    final s = stats;
    if (s != null) {
      _done.add(s);
      // Frame timings arrive in batches; report once they are in.
      Timer(const Duration(milliseconds: 1500), () => _report(s));
    }
  }

  void _onHover(PointerHoverEvent e) {
    if (!_isPen(e)) return;
    lastStylusSeenUs = _nowUs;
    hover = _toCanvas(e.localPosition);
    live.value++;
  }

  void _record(PointerEvent e) {
    final s = stats!;
    final evUs = e.timeStamp.inMicroseconds;
    s.events++;
    if (s.firstUs == 0) s.firstUs = evUs;
    if (s.lastUs != 0) s.intervalsUs.add(evUs - s.lastUs);
    s.lastUs = evUs;
    s.dartDelayUs.add(_nowUs - evUs);
    final p = _normPressure(e);
    s.minP = math.min(s.minP, p);
    s.maxP = math.max(s.maxP, p);
    s.minTilt = math.min(s.minTilt, e.tilt);
    s.maxTilt = math.max(s.maxTilt, e.tilt);
    s.buttons.add(e.buttons);
    s.raw.add(e.localPosition);
    hover = null;

    final pos = _toCanvas(e.localPosition);
    if (_erases(e)) {
      _eraseAt(pos);
      return;
    }
    final c = current;
    if (c == null) return;
    final pressure = settings.pressure ? p : 0.5;
    c.raw.add(InkPoint(pos, pressure, evUs));
    final scale = transform.getMaxScaleOnAxis();
    if (settings.smoothMode >= 2) {
      c.points
        ..clear()
        ..addAll(
          _arcSmooth(c.raw, LabSettings.arcRadii[settings.smoothMode] / scale),
        );
    } else {
      var q = pos;
      if (settings.smoothMode == 1) {
        q = Offset(fx!.filter(pos.dx, evUs), fy!.filter(pos.dy, evUs));
      }
      final minStep = 0.5 / scale;
      if (c.points.isEmpty || (q - c.points.last.pos).distance >= minStep) {
        c.points.add(InkPoint(q, pressure, evUs));
      }
    }
    predicted = settings.prediction ? _predict(c.points) : null;
    live.value++;
  }

  /// Linear extrapolation one frame (~11 ms at 90 Hz) ahead.
  Offset? _predict(List<InkPoint> pts) {
    if (pts.length < 3) return null;
    final a = pts[pts.length - 3], b = pts.last;
    final dt = (b.tUs - a.tUs) / 1000;
    if (dt <= 0) return null;
    final v = (b.pos - a.pos) / dt;
    return b.pos + v * 11;
  }

  void _eraseAt(Offset p) {
    final r = 12 / transform.getMaxScaleOnAxis();
    final before = strokes.length;
    strokes.removeWhere(
      (s) => s.points.any((q) => (q.pos - p).distance <= r + s.baseWidth),
    );
    if (strokes.length != before) _bakeAll();
  }

  // Latency bookkeeping ----------------------------------------------------

  /// Called while painting the live layer: ties this frame to the newest
  /// event it shows.
  void notePaint() {
    final c = current;
    final s = stats;
    if (c == null || s == null || c.points.isEmpty) return;
    _pending.add(_Sample(s.id, _nowUs, s.lastUs));
  }

  /// Frame timings while zooming/panning or erasing.
  String? interaction;
  final interactionFrames = <ui.FrameTiming>[];

  void _startInteraction(String name) {
    interaction = name;
    interactionFrames.clear();
  }

  void _endInteraction() {
    final name = interaction;
    if (name == null) return;
    final bake = bakeUs;
    Timer(const Duration(milliseconds: 1500), () {
      final f = [...interactionFrames];
      interaction = null;
      final build = [for (final t in f) t.buildDuration.inMicroseconds];
      final raster = [for (final t in f) t.rasterDuration.inMicroseconds];
      final total = [for (final t in f) t.totalSpan.inMicroseconds];
      final janky = f
          .where(
            (t) =>
                t.buildDuration.inMicroseconds > 11100 ||
                t.rasterDuration.inMicroseconds > 11100,
          )
          .length;
      debugPrint(
        'INKLAB interaction=$name frames=${f.length} janky=$janky '
        'build p50=${_ms(_pct(build, .5))} p95=${_ms(_pct(build, .95))} '
        'raster p50=${_ms(_pct(raster, .5))} p95=${_ms(_pct(raster, .95))} '
        'total p95=${_ms(_pct(total, .95))} max=${_ms(total.isEmpty ? -1 : total.reduce(math.max))} '
        'last_bake_record=${_ms(bake)}ms strokes=${strokes.length}',
      );
    });
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    if (interaction != null) interactionFrames.addAll(timings);
    for (final t in timings) {
      final build0 = t.timestampInMicroseconds(ui.FramePhase.buildStart);
      final build1 = t.timestampInMicroseconds(ui.FramePhase.buildFinish);
      final raster1 = t.timestampInMicroseconds(ui.FramePhase.rasterFinish);
      final matched = _pending
          .where((p) => p.paintUs >= build0 && p.paintUs <= build1)
          .toList();
      for (final m in matched) {
        final s = _done.followedBy([?stats]).where((x) => x.id == m.strokeId);
        if (s.isNotEmpty) s.first.rasterUs.add(raster1 - m.eventUs);
      }
      _pending.removeWhere(
        (p) => matched.contains(p) || p.paintUs < build0 - 2000000,
      );
    }
  }

  // Reporting --------------------------------------------------------------

  String _summary(StrokeStats s) {
    final durMs = (s.lastUs - s.firstUs) / 1000;
    final hz = durMs > 0 ? (s.events - 1) / durMs * 1000 : 0;
    return 'stroke=#${s.id} kind=${s.kind.name} events=${s.events} '
        'dur=${durMs.toStringAsFixed(0)}ms rate=${hz.toStringAsFixed(0)}Hz '
        'interval_p50=${_ms(_pct(s.intervalsUs, .5))}ms '
        'event→dart p50=${_ms(_pct(s.dartDelayUs, .5))} p95=${_ms(_pct(s.dartDelayUs, .95))} '
        'event→raster p50=${_ms(_pct(s.rasterUs, .5))} p95=${_ms(_pct(s.rasterUs, .95))} '
        'max=${_ms(s.rasterUs.isEmpty ? -1 : s.rasterUs.reduce(math.max))} frames=${s.rasterUs.length} '
        'pressure=${s.minP.toStringAsFixed(2)}..${s.maxP.toStringAsFixed(2)} '
        'tilt=${s.minTilt.toStringAsFixed(2)}..${s.maxTilt.toStringAsFixed(2)} '
        'buttons=${s.buttons.join('/')} '
        'jitter_px p50=${_jitter(s.raw, .5)} p90=${_jitter(s.raw, .9)} '
        '${_lineFit(s.raw)} smooth=${settings.smoothLabel} '
        'settings=[pressure:${settings.pressure} smooth:${settings.smoothing} '
        'predict:${settings.prediction} naive:${settings.naiveRepaint} '
        'outline:${settings.outline} bake:${settings.bake} '
        'strokes:${strokes.length} rejectedTouches:$rejectedTouches]';
  }

  void _report(StrokeStats s) {
    debugPrint('INKLAB ${_summary(s)}');
    debugPrint('INKLAB first-event #${s.id} ${s.firstEvent}');
  }

  void _refreshHud() {
    final s = stats;
    if (s == null) return;
    hud.value = _summary(s).replaceAll(' ', '\n');
  }

  // Baking -----------------------------------------------------------------
  // Committed strokes are rasterized once into an image at device resolution,
  // so a frame only composites one texture instead of replaying every vector.

  ui.Image? baked;
  Matrix4 bakedTransform = Matrix4.identity();
  Size viewSize = Size.zero;
  int bakeUs = 0; // last bake duration on the UI thread (recording only)

  double get _dpr => View.of(context).devicePixelRatio;

  ui.Image? _render(void Function(Canvas) draw) {
    if (viewSize.isEmpty) return null;
    final sw = Stopwatch()..start();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(_dpr);
    draw(canvas);
    final pic = rec.endRecording();
    final img = pic.toImageSync(
      (viewSize.width * _dpr).ceil(),
      (viewSize.height * _dpr).ceil(),
    );
    pic.dispose();
    bakeUs = sw.elapsedMicroseconds;
    return img;
  }

  void _bakeAll() {
    if (settings.bake) {
      final img = _render((canvas) {
        canvas.transform(transform.storage);
        for (final s in strokes) {
          _paintStroke(canvas, s, outline: settings.outline);
        }
      });
      baked?.dispose();
      baked = img;
      bakedTransform = transform.clone();
    }
    committedVersion.value++;
  }

  void _bakeAppend(Stroke stroke) {
    final previous = baked;
    if (!settings.bake || previous == null || bakedTransform != transform) {
      _bakeAll();
      return;
    }
    baked = _render((canvas) {
      canvas.save();
      canvas.scale(1 / _dpr);
      canvas.drawImage(previous, Offset.zero, Paint());
      canvas.restore();
      canvas.transform(transform.storage);
      _paintStroke(canvas, stroke, outline: settings.outline);
    });
    previous.dispose();
    committedVersion.value++;
  }

  // Stress -----------------------------------------------------------------

  void _stress() {
    final rnd = math.Random(42);
    final size = MediaQuery.sizeOf(context);
    for (var i = 0; i < 500; i++) {
      final st = Stroke(-1, palette[i % 3], 3, highlighter: false);
      var p = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      for (var j = 0; j < 60; j++) {
        p += Offset(rnd.nextDouble() * 8 - 4, rnd.nextDouble() * 8 - 4);
        st.points.add(InkPoint(p, rnd.nextDouble(), 0));
      }
      strokes.add(st);
    }
    _bakeAll();
  }

  // UI ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: RawGestureDetector(
              gestures: {
                _PalmAwareScale:
                    GestureRecognizerFactoryWithHandlers<_PalmAwareScale>(
                      () => _PalmAwareScale(this),
                      (r) {
                        Matrix4? start;
                        Offset? focalCanvas;
                        r
                          ..onStart = (d) {
                            _startInteraction('zoom');
                            start = transform.clone();
                            focalCanvas = _toCanvas(d.localFocalPoint);
                          }
                          ..onEnd = (_) {
                            _bakeAll();
                            _endInteraction();
                          }
                          ..onUpdate = (d) {
                            final s0 = start!.getMaxScaleOnAxis();
                            final s = (s0 * d.scale).clamp(0.25, 8.0);
                            {
                              transform = Matrix4.identity()
                                ..translateByDouble(
                                  d.localFocalPoint.dx,
                                  d.localFocalPoint.dy,
                                  0,
                                  1,
                                )
                                ..scaleByDouble(s, s, 1, 1)
                                ..translateByDouble(
                                  -focalCanvas!.dx,
                                  -focalCanvas!.dy,
                                  0,
                                  1,
                                );
                              view.value++;
                            }
                          };
                      },
                    ),
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onDown,
                onPointerMove: _onMove,
                onPointerUp: _onUp,
                onPointerCancel: _onUp,
                onPointerHover: _onHover,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFFFAFAF7)),
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: settings.naiveRepaint
                            ? _NaivePainter(this)
                            : _CommittedPainter(this),
                      ),
                    ),
                    RepaintBoundary(
                      child: CustomPaint(painter: _LivePainter(this)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(left: 8, top: 32, child: _Hud(hud)),
          Positioned(right: 8, top: 32, child: _toolbar()),
        ],
      ),
    );
  }

  Widget _toolbar() {
    Widget chip(String label, bool value, void Function(bool) set) =>
        FilterChip(
          label: Text(label),
          selected: value,
          onSelected: (v) => setState(() => set(v)),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 220,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              chip('Pressure', settings.pressure, (v) => settings.pressure = v),
              ActionChip(
                label: Text('Smooth: ${settings.smoothLabel}'),
                onPressed: () => setState(
                  () => settings.smoothMode = (settings.smoothMode + 1) % 5,
                ),
              ),
              chip(
                'Prediction',
                settings.prediction,
                (v) => settings.prediction = v,
              ),
              chip(
                'Stylus only',
                settings.stylusOnly,
                (v) => settings.stylusOnly = v,
              ),
              chip(
                'Naive repaint',
                settings.naiveRepaint,
                (v) => settings.naiveRepaint = v,
              ),
              chip('Outline', settings.outline, (v) {
                settings.outline = v;
                _bakeAll();
              }),
              chip('Bake', settings.bake, (v) {
                settings.bake = v;
                _bakeAll();
              }),
              chip(
                'Highlighter',
                settings.highlighter,
                (v) => settings.highlighter = v,
              ),
              ActionChip(
                label: const Text('Color'),
                avatar: CircleAvatar(backgroundColor: palette[colorIndex]),
                onPressed: () => setState(
                  () => colorIndex = (colorIndex + 1) % palette.length,
                ),
              ),
              ActionChip(label: const Text('+500 strokes'), onPressed: _stress),
              ActionChip(
                label: const Text('Reset view'),
                onPressed: () {
                  setState(() => transform = Matrix4.identity());
                  _bakeAll();
                },
              ),
              ActionChip(
                label: const Text('Clear'),
                onPressed: () {
                  strokes.clear();
                  _bakeAll();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scale/pan recognizer for fingers only, rejecting touches while the pen is
/// near the screen (palm rejection).
class _PalmAwareScale extends ScaleGestureRecognizer {
  _PalmAwareScale(this.lab)
    : super(
        supportedDevices: {PointerDeviceKind.touch, PointerDeviceKind.trackpad},
      );
  final _InkLabPageState lab;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (!lab.settings.stylusOnly) return false;
    if (lab.penNearby) {
      lab.rejectedTouches++;
      return false;
    }
    return super.isPointerAllowed(event);
  }
}

// ---------------------------------------------------------------------------
// Painting

/// Dart-side jitter: distance of each received point from the midpoint of its
/// neighbours, in logical px.
String _jitter(List<Offset> pts, double p) {
  if (pts.length < 3) return '—';
  final d = <double>[
    for (var i = 1; i < pts.length - 1; i++)
      (pts[i] - (pts[i - 1] + pts[i + 1]) / 2).distance,
  ]..sort();
  return d[((d.length - 1) * p).round()].toStringAsFixed(3);
}

/// Arc-length smoothing: resample the raw polyline every radius/4 and apply a
/// triangular moving average over ±radius of arc length. The window shrinks
/// at the ends, so the newest point stays under the pen tip (no added lag);
/// it is re-smoothed as more input arrives.
List<InkPoint> _arcSmooth(List<InkPoint> raw, double radius) {
  if (raw.length < 3 || radius <= 0) return [...raw];
  final h = radius / 4;
  final res = <InkPoint>[raw.first];
  var dist = 0.0; // distance travelled since the last emitted sample
  for (var i = 1; i < raw.length; i++) {
    final a = raw[i - 1], b = raw[i];
    final seg = (b.pos - a.pos).distance;
    if (seg == 0) continue;
    var t = h - dist;
    while (t <= seg) {
      final f = t / seg;
      res.add(
        InkPoint(
          Offset.lerp(a.pos, b.pos, f)!,
          a.pressure + (b.pressure - a.pressure) * f,
          b.tUs,
        ),
      );
      t += h;
    }
    dist = seg - (t - h);
  }
  res.add(raw.last);
  const k = 4;
  final out = <InkPoint>[];
  for (var i = 0; i < res.length; i++) {
    final w = math.min(k, math.min(i, res.length - 1 - i));
    var sx = 0.0, sy = 0.0, sp = 0.0, sw = 0.0;
    for (var j = -w; j <= w; j++) {
      final wt = (w + 1 - j.abs()).toDouble();
      final q = res[i + j];
      sx += q.pos.dx * wt;
      sy += q.pos.dy * wt;
      sp += q.pressure * wt;
      sw += wt;
    }
    out.add(InkPoint(Offset(sx / sw, sy / sw), sp / sw, res[i].tUs));
  }
  return out;
}

/// Straight-line fit of the received points (for ruler tests): distance of
/// each point from the total-least-squares line, in logical px.
String _lineFit(List<Offset> pts) {
  if (pts.length < 10) return 'line=—';
  final n = pts.length;
  final mx = pts.fold(0.0, (a, p) => a + p.dx) / n;
  final my = pts.fold(0.0, (a, p) => a + p.dy) / n;
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (final p in pts) {
    sxx += (p.dx - mx) * (p.dx - mx);
    syy += (p.dy - my) * (p.dy - my);
    sxy += (p.dx - mx) * (p.dy - my);
  }
  final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
  final nx = -math.sin(angle), ny = math.cos(angle);
  final d = [for (final p in pts) ((p.dx - mx) * nx + (p.dy - my) * ny).abs()]
    ..sort();
  final length = (pts.last - pts.first).distance;
  return 'line len=${length.toStringAsFixed(0)}px '
      'dev p50=${d[n ~/ 2].toStringAsFixed(2)} '
      'p90=${d[(n * 0.9).floor()].toStringAsFixed(2)} '
      'max=${d.last.toStringAsFixed(2)}';
}

double _radius(Stroke s, double pressure) =>
    s.baseWidth / 2 * (0.35 + 1.3 * pressure);

/// Filled variable-width outline (perfect-freehand style): pressure is
/// low-passed, edges are offset along smoothed normals and joined with
/// quadratic curves through midpoints.
void _paintOutline(Canvas canvas, Stroke s, Paint paint, Offset? tail) {
  final pos = [for (final p in s.points) p.pos, ?tail];
  final n = pos.length;
  final radii = <double>[];
  var ema = s.points.first.pressure;
  for (var i = 0; i < n; i++) {
    ema += 0.2 * (s.points[math.min(i, s.points.length - 1)].pressure - ema);
    radii.add(_radius(s, ema));
  }
  final left = <Offset>[], right = <Offset>[];
  var normal = const Offset(0, 1);
  for (var i = 0; i < n; i++) {
    // Tangent over a wider window (±3 points) keeps normals stable when
    // samples are very close together.
    final t = pos[math.min(i + 3, n - 1)] - pos[math.max(i - 3, 0)];
    if (t.distance > 1e-3) normal = Offset(-t.dy, t.dx) / t.distance;
    left.add(pos[i] + normal * radii[i]);
    right.add(pos[i] - normal * radii[i]);
  }
  final path = Path()..moveTo(left.first.dx, left.first.dy);
  void curveThrough(List<Offset> pts) {
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = (pts[i] + pts[i + 1]) / 2;
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
  }

  curveThrough(left);
  path.lineTo(right.last.dx, right.last.dy);
  curveThrough(right.reversed.toList());
  path.close();
  final fill = Paint()
    ..color = paint.color
    ..style = PaintingStyle.fill;
  canvas.drawPath(path, fill);
  // Round caps.
  canvas.drawCircle(pos.first, radii.first, fill);
  canvas.drawCircle(pos.last, radii.last, fill);
}

void _paintStroke(
  Canvas canvas,
  Stroke s, {
  Offset? tail,
  bool outline = false,
}) {
  final paint = Paint()
    ..color = s.highlighter ? s.color.withValues(alpha: 0.35) : s.color
    ..strokeCap = s.highlighter ? StrokeCap.square : StrokeCap.round
    ..style = PaintingStyle.stroke
    ..blendMode = s.highlighter ? BlendMode.multiply : BlendMode.srcOver;
  final pts = s.points;
  if (pts.length == 1) {
    canvas.drawCircle(
      pts.first.pos,
      s.baseWidth / 2,
      paint..style = PaintingStyle.fill,
    );
    return;
  }
  if (outline && !s.highlighter) {
    _paintOutline(canvas, s, paint, tail);
    return;
  }
  if (s.highlighter) {
    // Constant width, one path so overlaps do not darken.
    final path = Path()..moveTo(pts.first.pos.dx, pts.first.pos.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.pos.dx, p.pos.dy);
    }
    if (tail != null) path.lineTo(tail.dx, tail.dy);
    canvas.drawPath(path, paint..strokeWidth = s.baseWidth);
    return;
  }
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final pressure = (a.pressure + b.pressure) / 2;
    paint.strokeWidth = s.baseWidth * (0.25 + 1.5 * pressure);
    canvas.drawLine(a.pos, b.pos, paint);
  }
  if (tail != null) {
    paint
      ..strokeWidth = s.baseWidth * (0.25 + 1.5 * pts.last.pressure)
      ..color = paint.color.withValues(alpha: 0.5);
    canvas.drawLine(pts.last.pos, tail, paint);
  }
}

class _CommittedPainter extends CustomPainter {
  _CommittedPainter(this.lab)
    : super(repaint: Listenable.merge([lab.committedVersion, lab.view]));
  final _InkLabPageState lab;

  @override
  void paint(Canvas canvas, Size size) {
    final firstLayout = lab.viewSize.isEmpty;
    lab.viewSize = size;
    if (firstLayout) Future.microtask(lab._bakeAll);
    final img = lab.baked;
    if (lab.settings.bake && img != null) {
      // During pan/zoom the old bake is transformed until it is re-baked.
      canvas.transform(
        (lab.transform * Matrix4.inverted(lab.bakedTransform) as Matrix4)
            .storage,
      );
      canvas.scale(1 / lab._dpr);
      canvas.drawImage(
        img,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    canvas.transform(lab.transform.storage);
    for (final s in lab.strokes) {
      _paintStroke(canvas, s, outline: lab.settings.outline);
    }
  }

  @override
  bool shouldRepaint(_CommittedPainter old) => true;
}

class _LivePainter extends CustomPainter {
  _LivePainter(this.lab)
    : super(repaint: Listenable.merge([lab.live, lab.view]));
  final _InkLabPageState lab;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.transform(lab.transform.storage);
    final c = lab.current;
    if (c != null && c.points.isNotEmpty) {
      _paintStroke(
        canvas,
        c,
        tail: lab.predicted,
        outline: lab.settings.outline,
      );
      lab.notePaint();
    }
    final h = lab.hover;
    if (h != null) {
      canvas.drawCircle(
        h,
        3,
        Paint()..color = Colors.indigo.withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_LivePainter old) => true;
}

/// Baseline: repaints every stroke on every input event.
class _NaivePainter extends CustomPainter {
  _NaivePainter(this.lab)
    : super(
        repaint: Listenable.merge([lab.committedVersion, lab.live, lab.view]),
      );
  final _InkLabPageState lab;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.transform(lab.transform.storage);
    for (final s in lab.strokes) {
      _paintStroke(canvas, s, outline: lab.settings.outline);
    }
  }

  @override
  bool shouldRepaint(_NaivePainter old) => true;
}

class _Hud extends StatelessWidget {
  const _Hud(this.text);
  final ValueListenable<String> text;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: IgnorePointer(
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(8),
        color: Colors.black.withValues(alpha: 0.6),
        child: ValueListenableBuilder(
          valueListenable: text,
          builder: (_, v, _) => Text(
            v,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    ),
  );
}
