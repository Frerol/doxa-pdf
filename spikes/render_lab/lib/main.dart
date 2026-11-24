// SPDX-License-Identifier: GPL-3.0-or-later
//
// Render Lab — throwaway prototype for Spike A (issue #5): continuous
// vertical reader with low-res page previews, 512 px tiles per zoom bucket,
// an LRU image cache, fling and pinch zoom. Logs "RENDERLAB ..." lines.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'engine.dart';

const filesDir =
    '/storage/emulated/0/Android/data/io.github.frerol.doxapdf.render_lab/files';
const tilePx = 512; // physical pixels
const previewPx = 360; // physical width of page previews
const gap = 8.0; // logical px between pages
const cacheBudget = 160 << 20; // bytes of decoded images

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: RenderLab()),
);

class _Entry {
  _Entry(this.image, this.bytes);
  final ui.Image image;
  final int bytes;
}

class RenderLab extends StatefulWidget {
  const RenderLab({super.key});

  @override
  State<RenderLab> createState() => _RenderLabState();
}

class _RenderLabState extends State<RenderLab>
    with SingleTickerProviderStateMixin {
  EngineClient? engine;
  String? docName;
  List<String> files = [];

  // Layout (logical px at zoom 1).
  Float64List sizes = Float64List(0); // pt
  final pageTop = <double>[];
  final pageH = <double>[];
  double viewW = 0, viewH = 0, dpr = 1, docH = 0;

  // View: screen = (doc - offset) * zoom.
  double zoom = 1, ox = 0, oy = 0;
  final repaint = ValueNotifier<int>(0);

  // Cache and requests.
  final cache = LinkedHashMap<String, _Entry>();
  int cacheBytes = 0;
  final pendingKey = <int, String>{};
  final pendingKeys = <String>{};
  final requestedAt = <int, int>{};
  int nextId = 0, gen = 0;

  // Metrics.
  final stopwatch = Stopwatch()..start();
  int? openAt;
  bool firstPainted = false;
  bool interacting = false;
  final frames = <ui.FrameTiming>[];
  final tileLatency = <int>[]; // request -> decoded, µs
  final renderMs = <double>[];
  int blankFrames = 0, paintedFrames = 0;
  final hud = ValueNotifier<String>('');

  late final Ticker ticker = createTicker(_onTick);
  Simulation? flingX, flingY;
  Duration flingStart = Duration.zero;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _listFiles();
    // Files may be adb-pushed after launch.
    Timer.periodic(const Duration(seconds: 2), (_) {
      if (files.isEmpty) _listFiles();
    });
    EngineClient.spawn().then((e) {
      engine = e;
      e.replies.listen(_onReply);
      setState(() {});
    });
  }

  void _listFiles() {
    final dir = Directory(filesDir);
    if (!dir.existsSync()) return;
    setState(() {
      files =
          dir
              .listSync()
              .whereType<File>()
              .map((f) => f.path)
              .where((p) => p.endsWith('.pdf'))
              .toList()
            ..sort();
    });
  }

  void _log(String s) => debugPrint('RENDERLAB $s');

  void _open(String path) {
    for (final e in cache.values) {
      e.image.dispose();
    }
    cache.clear();
    cacheBytes = 0;
    pendingKey.clear();
    pendingKeys.clear();
    firstPainted = false;
    blankFrames = paintedFrames = 0;
    tileLatency.clear();
    renderMs.clear();
    zoom = 1;
    ox = oy = 0;
    docName = path.split('/').last;
    openAt = stopwatch.elapsedMicroseconds;
    engine!.open(path);
  }

  // Engine replies ---------------------------------------------------------

  void _onReply(Map<String, Object?> m) {
    switch (m['op']) {
      case 'opened':
        sizes = m['sizes']! as Float64List;
        _layout();
        _log(
          'open $docName pages=${m['pages']} engineOpen=${(m['openMs']! as double).toStringAsFixed(1)}ms',
        );
        _ensure();
        repaint.value++;
      case 'tile':
        final id = m['id']! as int;
        final key = pendingKey.remove(id);
        if (key == null) return;
        renderMs.add(m['ms']! as double);
        final data = (m['data']! as TransferableTypedData)
            .materialize()
            .asUint8List();
        final w = m['w']! as int, h = m['h']! as int;
        ui.decodeImageFromPixels(data, w, h, ui.PixelFormat.rgba8888, (img) {
          pendingKeys.remove(key);
          tileLatency.add(
            stopwatch.elapsedMicroseconds - requestedAt.remove(id)!,
          );
          cache.remove(key)?.image.dispose();
          cache[key] = _Entry(img, w * h * 4);
          cacheBytes += w * h * 4;
          _evict();
          repaint.value++;
        });
      case 'dropped':
        for (final id in m['ids']! as List) {
          final key = pendingKey.remove(id as int);
          if (key != null) pendingKeys.remove(key);
          requestedAt.remove(id);
        }
      case 'error':
        _log('ERROR ${m['message']}');
    }
  }

  void _evict() {
    final visible = _visibleKeys();
    final keys = cache.keys.toList();
    for (final k in keys) {
      if (cacheBytes <= cacheBudget) break;
      if (visible.contains(k)) continue;
      final e = cache.remove(k)!;
      cacheBytes -= e.bytes;
      e.image.dispose();
    }
  }

  // Layout and requests ----------------------------------------------------

  void _layout() {
    pageTop.clear();
    pageH.clear();
    var y = 0.0;
    for (var i = 0; i < sizes.length ~/ 2; i++) {
      final h = sizes[i * 2 + 1] * viewW / sizes[i * 2];
      pageTop.add(y);
      pageH.add(h);
      y += h + gap;
    }
    docH = y;
  }

  int get bucket =>
      math.pow(2, math.max(0, (math.log(zoom) / math.ln2).ceil())).toInt();

  Iterable<int> _pagesIn(double top, double bottom) sync* {
    for (var i = 0; i < pageTop.length; i++) {
      if (pageTop[i] > bottom) break;
      if (pageTop[i] + pageH[i] >= top) yield i;
    }
  }

  /// Tiles of page [i] at the current bucket that intersect doc rect y0..y1.
  Iterable<(String, Map<String, Object?>, Rect)> _tiles(
    int i,
    double x0,
    double x1,
    double y0,
    double y1,
  ) sync* {
    final zb = bucket;
    final s = viewW / sizes[i * 2] * zb * dpr; // physical px per pt
    final wPx = (sizes[i * 2] * s).ceil(), hPx = (sizes[i * 2 + 1] * s).ceil();
    final toLogical = 1 / (zb * dpr);
    for (var ty = 0; ty * tilePx < hPx; ty++) {
      final top = pageTop[i] + ty * tilePx * toLogical;
      final bottom = top + tilePx * toLogical;
      if (bottom < y0 || top > y1) continue;
      for (var tx = 0; tx * tilePx < wPx; tx++) {
        final left = tx * tilePx * toLogical, right = left + tilePx * toLogical;
        if (right < x0 || left > x1) continue;
        final w = math.min(tilePx, wPx - tx * tilePx),
            h = math.min(tilePx, hPx - ty * tilePx);
        yield (
          't:$i:$zb:$tx:$ty',
          {
            'page': i,
            'scale': s,
            'x': tx * tilePx,
            'y': ty * tilePx,
            'w': w,
            'h': h,
          },
          Rect.fromLTWH(left, top, w * toLogical, h * toLogical),
        );
      }
    }
  }

  Map<String, Object?> _previewReq(int i) {
    final s = previewPx / sizes[i * 2];
    return {
      'page': i,
      'scale': s,
      'x': 0,
      'y': 0,
      'w': previewPx,
      'h': (sizes[i * 2 + 1] * s).ceil(),
    };
  }

  Set<String> _visibleKeys() {
    final y0 = oy, y1 = oy + viewH / zoom, x0 = ox, x1 = ox + viewW / zoom;
    return {
      for (final i in _pagesIn(y0, y1)) ...[
        'p:$i',
        for (final t in _tiles(i, x0, x1, y0, y1)) t.$1,
      ],
    };
  }

  void _request(String key, Map<String, Object?> req, int pri) {
    if (cache.containsKey(key) || pendingKeys.contains(key)) {
      if (cache.containsKey(key)) cache[key] = cache.remove(key)!; // LRU touch
      return;
    }
    final id = nextId++;
    pendingKey[id] = key;
    pendingKeys.add(key);
    requestedAt[id] = stopwatch.elapsedMicroseconds;
    engine!.render({...req, 'id': id, 'gen': gen, 'pri': pri});
  }

  void _ensure() {
    if (engine == null || pageTop.isEmpty) return;
    engine!.generation(++gen);
    final screenH = viewH / zoom;
    final y0 = oy, y1 = oy + screenH, x0 = ox, x1 = ox + viewW / zoom;
    final visible = _pagesIn(y0, y1).toList();
    for (final i in visible) {
      _request('p:$i', _previewReq(i), priVisiblePreview);
    }
    for (final i in visible) {
      for (final t in _tiles(i, x0, x1, y0, y1)) {
        _request(t.$1, t.$2, priVisibleTile);
      }
    }
    // One screen of look-ahead in both directions.
    for (final i in _pagesIn(y0 - screenH, y1 + screenH)) {
      _request('p:$i', _previewReq(i), priNearPreview);
    }
    for (final i in _pagesIn(y1, y1 + screenH)) {
      for (final t in _tiles(i, x0, x1, y1, y1 + screenH)) {
        _request(t.$1, t.$2, priNearTile);
      }
    }
  }

  // Gestures ---------------------------------------------------------------

  double? z0;
  Offset? focalDoc;

  void _clamp() {
    ox = ox.clamp(0, math.max(0, viewW - viewW / zoom));
    oy = oy.clamp(0, math.max(0, docH - viewH / zoom));
  }

  void _changed() {
    _clamp();
    _ensure();
    repaint.value++;
  }

  void _onScaleStart(ScaleStartDetails d) {
    ticker.stop();
    _startInteraction();
    z0 = zoom;
    focalDoc = Offset(
      ox + d.localFocalPoint.dx / zoom,
      oy + d.localFocalPoint.dy / zoom,
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    zoom = (z0! * d.scale).clamp(1.0, 8.0);
    ox = focalDoc!.dx - d.localFocalPoint.dx / zoom;
    oy = focalDoc!.dy - d.localFocalPoint.dy / zoom;
    _changed();
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final v = d.velocity.pixelsPerSecond;
    if (d.pointerCount <= 1 && v.distance > 50) {
      flingX = ClampingScrollSimulation(position: ox, velocity: -v.dx / zoom);
      flingY = ClampingScrollSimulation(position: oy, velocity: -v.dy / zoom);
      flingStart = Duration.zero;
      ticker.start();
    } else {
      _endInteraction();
    }
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    ox = flingX!.x(t);
    oy = flingY!.x(t);
    _changed();
    if (flingX!.isDone(t) && flingY!.isDone(t)) {
      ticker.stop();
      _endInteraction();
    }
  }

  void _startInteraction() {
    interacting = true;
    frames.clear();
    blankFrames = paintedFrames = 0;
  }

  void _endInteraction() {
    interacting = false;
    Future.delayed(const Duration(milliseconds: 1500), _report);
  }

  void _onTimings(List<ui.FrameTiming> t) {
    if (interacting) frames.addAll(t);
  }

  int _pct(List<num> v, double p) {
    if (v.isEmpty) return -1;
    final s = [...v]..sort();
    return s[((s.length - 1) * p).round()].round();
  }

  int _rssMb() {
    try {
      final l = File('/proc/self/status')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('VmRSS'));
      return int.parse(l.split(RegExp(r'\s+'))[1]) ~/ 1024;
    } catch (_) {
      return -1;
    }
  }

  void _report() {
    final build = [for (final f in frames) f.buildDuration.inMicroseconds];
    final raster = [for (final f in frames) f.rasterDuration.inMicroseconds];
    final janky = frames
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > 11100 ||
              f.rasterDuration.inMicroseconds > 11100,
        )
        .length;
    final line =
        'interaction doc=$docName zoom=${zoom.toStringAsFixed(2)} bucket=$bucket '
        'frames=${frames.length} janky=$janky build_p95=${_pct(build, .95) / 1000}ms raster_p95=${_pct(raster, .95) / 1000}ms '
        'blankFrames=$blankFrames/$paintedFrames tileLatency_p50=${_pct(tileLatency, .5) / 1000}ms p95=${_pct(tileLatency, .95) / 1000}ms '
        'render_p50=${_pct(renderMs, .5)}ms p95=${_pct(renderMs, .95)}ms cache=${cacheBytes >> 20}MB/${cache.length} rss=${_rssMb()}MB';
    _log(line);
    hud.value = line.replaceAll(' ', '\n');
  }

  // Painting ---------------------------------------------------------------

  void onPainted(bool blank) {
    paintedFrames++;
    if (blank) blankFrames++;
    if (!firstPainted && !blank && openAt != null) {
      firstPainted = true;
      final ms = (stopwatch.elapsedMicroseconds - openAt!) / 1000;
      _log(
        'firstPagePainted doc=$docName ${ms.toStringAsFixed(1)}ms after open request',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  IconButton(
                    onPressed: _listFiles,
                    icon: const Icon(Icons.refresh),
                  ),
                  for (final f in files)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: ActionChip(
                        label: Text(f.split('/').last),
                        onPressed: engine == null ? null : () => _open(f),
                      ),
                    ),
                  if (files.isEmpty)
                    const Center(
                      child: Text(
                        'adb push *.pdf to the app files dir, then refresh',
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth, h = c.maxHeight;
                  if (w != viewW || h != viewH) {
                    viewW = w;
                    viewH = h;
                    dpr = MediaQuery.devicePixelRatioOf(context);
                    if (sizes.isNotEmpty) {
                      _layout();
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _changed(),
                      );
                    }
                  }
                  return Stack(
                    children: [
                      GestureDetector(
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        onScaleEnd: _onScaleEnd,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: Size(w, h),
                            painter: _Painter(this),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: IgnorePointer(
                          child: ValueListenableBuilder(
                            valueListenable: hud,
                            builder: (_, v, _) => v.isEmpty
                                ? const SizedBox()
                                : Container(
                                    padding: const EdgeInsets.all(6),
                                    color: Colors.black54,
                                    child: Text(
                                      v,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.lab) : super(repaint: lab.repaint);
  final _RenderLabState lab;

  @override
  void paint(Canvas canvas, Size size) {
    // Clip to our own bounds: drawColor would paint the whole screen.
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF5F6368));
    if (lab.pageTop.isEmpty) return;
    canvas.save();
    canvas.scale(lab.zoom);
    canvas.translate(-lab.ox, -lab.oy);
    final y0 = lab.oy, y1 = lab.oy + lab.viewH / lab.zoom;
    final x0 = lab.ox, x1 = lab.ox + lab.viewW / lab.zoom;
    final white = Paint()..color = Colors.white;
    final img = Paint()..filterQuality = FilterQuality.low;
    var blank = false;
    for (final i in lab._pagesIn(y0, y1)) {
      final pageRect = Rect.fromLTWH(
        0,
        lab.pageTop[i],
        lab.viewW,
        lab.pageH[i],
      );
      canvas.drawRect(pageRect, white);
      final preview = lab.cache['p:$i'];
      if (preview != null) {
        final im = preview.image;
        canvas.drawImageRect(
          im,
          Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
          pageRect,
          img,
        );
      } else {
        blank = true;
      }
      for (final t in lab._tiles(i, x0, x1, y0, y1)) {
        final e = lab.cache[t.$1];
        if (e == null) continue;
        final im = e.image;
        canvas.drawImageRect(
          im,
          Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
          t.$3,
          img,
        );
      }
    }
    canvas.restore();
    lab.onPainted(blank);
  }

  @override
  bool shouldRepaint(_Painter old) => true;
}
