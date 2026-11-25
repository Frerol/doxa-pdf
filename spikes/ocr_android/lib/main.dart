// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'engine.dart';

void main() => runApp(const MaterialApp(home: OcrLab()));

const _channel = MethodChannel('ocr_lab');

void _log(String message) => debugPrint('OCRLAB $message');

class OcrLab extends StatefulWidget {
  const OcrLab({super.key});

  @override
  State<OcrLab> createState() => _OcrLabState();
}

class _OcrLabState extends State<OcrLab> {
  final _engine = Engine.start();
  final _query = TextEditingController();
  final _ink = ValueNotifier<List<List<Offset>>>([]);
  final _transform = TransformationController();
  final _inkByPage = <int, List<List<Offset>>>{};

  String? _source;
  String? _saved;
  String _status = 'Open a scanned PDF';
  int _page = 0;
  int _pages = 0;
  int _viewRequest = 0;
  int _job = 0;
  int? _pen;
  ui.Image? _image;
  List<SearchHit> _hits = [];
  int _hit = 0;
  bool _busy = false;
  bool _running = false;
  bool _cancelled = false;
  Stopwatch? _cancelWatch;
  String? _trace;
  int _frames = 0;
  int _slow = 0;
  int _verySlow = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    unawaited(
      _engine.then<void>(
        (_) {},
        onError: (Object error) {
          if (mounted) setState(() => _status = error.toString());
        },
      ),
    );
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    _query.dispose();
    _transform.dispose();
    _ink.dispose();
    _image?.dispose();
    super.dispose();
  }

  void _timings(List<ui.FrameTiming> timings) {
    if (_trace == null) return;
    for (final timing in timings) {
      final us = timing.totalSpan.inMicroseconds;
      _frames++;
      if (us > 16700) _slow++;
      if (us > 32000) _verySlow++;
    }
  }

  void _startTrace(String label) {
    _trace = label;
    _frames = _slow = _verySlow = 0;
    _log('trace=$label frames_start');
  }

  void _endTrace() {
    _log(
      'trace=$_trace frames=$_frames frames_gt_16_7ms=$_slow '
      'frames_gt_32ms=$_verySlow',
    );
    _trace = null;
  }

  Future<void> _memory(int job, String phase) async {
    try {
      final lines = await File('/proc/self/status').readAsLines();
      final values = lines.where(
        (line) => line.startsWith('VmHWM:') || line.startsWith('VmRSS:'),
      );
      _log(
        'job=$job memory=$phase ${values.map((line) => line.replaceAll(RegExp(r'\s+'), ' ')).join(' ')}',
      );
    } on FileSystemException catch (error) {
      _log('job=$job memory=$phase error=$error');
    }
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    String? candidate;
    try {
      candidate = await _channel.invokeMethod<String>('pick');
      if (candidate == null) return;
      final engine = await _engine;
      final count = await engine.call<int>('open', [candidate]);
      final old = _source;
      setState(() {
        _source = candidate;
        _pages = count;
        _saved = null;
        _hits = [];
        _inkByPage.clear();
        _status = 'Ready';
      });
      if (old != null) await File(old).parent.delete(recursive: true);
      await _showPage(0);
    } catch (error) {
      if (candidate != null && candidate != _source) {
        await File(candidate).parent.delete(recursive: true);
      }
      setState(() => _status = error.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _showPage(int page) async {
    final request = ++_viewRequest;
    final old = _image;
    setState(() {
      _page = page;
      _image = null;
    });
    old?.dispose();
    _pen = null;
    _ink.value = _inkByPage.putIfAbsent(page, () => []);
    _transform.value = Matrix4.identity();
    try {
      final engine = await _engine;
      if (request != _viewRequest) return;
      final raster = await engine.call<Raster>('preview', [page]);
      if (request != _viewRequest) return;
      final image = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        raster.data.materialize().asUint8List(),
        raster.width,
        raster.height,
        ui.PixelFormat.bgra8888,
        image.complete,
      );
      final decoded = await image.future;
      if (!mounted || request != _viewRequest) {
        decoded.dispose();
        return;
      }
      setState(() => _image = decoded);
    } catch (error) {
      if (mounted && request == _viewRequest) {
        setState(() => _status = error.toString());
      }
    }
  }

  void _checkCancellation() {
    if (_cancelled) throw const _Cancelled();
  }

  Future<void> _cancel() async {
    setState(() {
      _cancelled = true;
      _cancelWatch = Stopwatch()..start();
      _status = 'Cancelling…';
    });
    _log('job=$_job cancel_requested');
    await _channel.invokeMethod<void>('cancel');
  }

  Future<void> _ocr(List<int> pages) async {
    final source = _source!;
    final job = ++_job;
    final directory = File(source).parent.path;
    final pending = File('$directory/pending.pdf');
    final target = '$directory/ocr-copy.pdf';
    setState(() {
      _busy = _running = true;
      _cancelled = false;
      _cancelWatch = null;
      _status = 'Preparing language models…';
    });
    if (_trace != null) _endTrace();
    _startTrace('ocr-$job');
    final batch = Stopwatch()..start();
    await _memory(job, 'before');
    final timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_memory(job, 'during')),
    );
    Engine? engine;
    try {
      _checkCancellation();
      final initWatch = Stopwatch()..start();
      final initMs = (await _channel.invokeMethod<double>('init'))!;
      _log(
        'job=$job model_init_ms=$initMs model_prepare_ms=${elapsedMs(initWatch)}',
      );
      _checkCancellation();
      engine = await _engine;
      await engine.call<void>('begin', [source]);
      final timings = <String>[];
      for (final page in pages) {
        _checkCancellation();
        setState(() => _status = 'Rendering page ${page + 1}…');
        final total = Stopwatch()..start();
        final stage = Stopwatch()..start();
        final raster = await engine.call<Raster>('raster', [page]);
        final renderMs = elapsedMs(stage);
        _checkCancellation();
        setState(() => _status = 'Recognizing page ${page + 1}…');
        _log('job=$job page=${page + 1} stage=recognition_start');
        final result = (await _channel.invokeMapMethod<String, Object?>(
          'recognize',
          {
            'pixels': raster.data.materialize().asUint8List(),
            'width': raster.width,
            'height': raster.height,
          },
        ))!;
        _checkCancellation();
        stage.reset();
        final count = await engine.call<int>('write', [
          page,
          raster.width,
          raster.height,
          result['words']! as List<Object?>,
        ]);
        final line =
            'job=$job page=${page + 1} '
            'width=${raster.width} height=${raster.height} words=$count '
            'model_init_ms=${page == pages.first ? initMs : 0} '
            'render_ms=$renderMs ocr_ms=${result['ocr_ms']} '
            'write_ms=${elapsedMs(stage)} page_ms=${elapsedMs(total)}';
        timings.add(line);
        _log('$line stage=page_done');
        _checkCancellation();
      }
      setState(() => _status = 'Saving and verifying PDF…');
      _log('job=$job stage=save_start');
      final output = await engine.call<({double saveMs, double verifyMs})>(
        'save',
        [pending.path],
      );
      _checkCancellation();
      // A synchronous same-directory rename is the publication boundary.
      pending.renameSync(target);
      setState(() {
        _saved = target;
        _hits = [];
        _status = 'Verified copy saved. Search for a recognized word.';
      });
      for (final line in timings) {
        _log(
          '$line full_save_ms=${output.saveMs} verified_ms=${output.verifyMs} '
          'total_ms=${elapsedMs(batch)} stage=published',
        );
      }
    } catch (error) {
      setState(() => _status = _cancelled ? 'OCR cancelled' : error.toString());
      _log(
        'job=$job outcome=${_cancelled ? 'cancelled' : 'error'} '
        'elapsed_ms=${elapsedMs(batch)}'
        '${_cancelWatch == null ? '' : ' cancel_ms=${elapsedMs(_cancelWatch!)}'}'
        '${_cancelled ? '' : ' error=$error'}',
      );
    } finally {
      timer.cancel();
      try {
        await engine?.call<void>('abort');
        if (await pending.exists()) await pending.delete();
      } finally {
        await _memory(job, 'after');
        _endTrace();
        setState(() => _busy = _running = false);
      }
    }
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) {
      setState(() => _hits = []);
      return;
    }
    setState(() => _busy = true);
    try {
      final engine = await _engine;
      final hits = await engine.call<List<SearchHit>>('search', [
        _saved!,
        query,
      ]);
      setState(() {
        _hits = hits;
        _hit = 0;
        _status = '${hits.length} search hits';
      });
      _log('search hits=${hits.length}');
      if (hits.isNotEmpty && hits.first.page != _page) {
        await _showPage(hits.first.page);
      }
    } catch (error) {
      setState(() => _status = error.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  void _penDown(PointerDownEvent event) {
    if (_pen != null ||
        (event.kind != ui.PointerDeviceKind.stylus &&
            event.kind != ui.PointerDeviceKind.invertedStylus)) {
      return;
    }
    setState(() => _pen = event.pointer);
    _ink.value = [
      ..._ink.value,
      [event.localPosition],
    ];
    _inkByPage[_page] = _ink.value;
  }

  void _penMove(PointerMoveEvent event) {
    if (event.pointer != _pen) return;
    _ink.value.last.add(event.localPosition);
    // Signal painters without rebuilding the image or viewport.
    _ink.value = [..._ink.value];
  }

  void _penEnd(PointerEvent event) {
    if (event.pointer == _pen) setState(() => _pen = null);
  }

  Widget _view(ui.Image image) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = width * image.height / image.width;
      return InteractiveViewer(
        transformationController: _transform,
        constrained: false,
        maxScale: 6,
        panEnabled: _pen == null,
        scaleEnabled: _pen == null,
        child: Listener(
          onPointerDown: _penDown,
          onPointerMove: _penMove,
          onPointerUp: _penEnd,
          onPointerCancel: _penEnd,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RawImage(image: image, fit: BoxFit.fill),
                CustomPaint(
                  painter: _Overlay(
                    _ink,
                    _hits
                        .where((hit) => hit.page == _page)
                        .expand((hit) => hit.rectangles)
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Doxa OCR Lab')),
    body: SafeArea(
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy ? null : _pick,
                child: const Text('Open PDF'),
              ),
              TextButton(
                onPressed: _busy || _source == null
                    ? null
                    : () => _ocr([_page]),
                child: const Text('OCR this page'),
              ),
              TextButton(
                onPressed: _busy || _pages < 3 ? null : () => _ocr([0, 1, 2]),
                child: const Text('OCR first 3 pages'),
              ),
              TextButton(
                onPressed: _busy || _source == null
                    ? null
                    : () => _ocr(List.generate(_pages, (index) => index)),
                child: const Text('OCR whole document'),
              ),
              TextButton(
                onPressed: _running && !_cancelled ? _cancel : null,
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: _busy || _source == null
                    ? null
                    : () {
                        setState(() {
                          if (_trace == null) {
                            _startTrace('control');
                          } else {
                            _endTrace();
                          }
                        });
                      },
                child: Text(
                  _trace == 'control'
                      ? 'End control trace'
                      : 'Start control trace',
                ),
              ),
            ],
          ),
          if (_source != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: _page > 0 ? () => _showPage(_page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${_page + 1} / $_pages'),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: _page + 1 < _pages
                      ? () => _showPage(_page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          if (_saved != null)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    enabled: !_busy,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      labelText: 'Search verified copy',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _search,
                  child: const Text('Search'),
                ),
                if (_hits.isNotEmpty)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _hit = (_hit + 1) % _hits.length;
                            final page = _hits[_hit].page;
                            if (page != _page) unawaited(_showPage(page));
                          },
                    child: const Text('Next hit'),
                  ),
              ],
            ),
          Text(_status),
          Expanded(
            child: _image == null ? const SizedBox.expand() : _view(_image!),
          ),
        ],
      ),
    ),
  );
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _Overlay extends CustomPainter {
  _Overlay(this.ink, this.hits) : super(repaint: ink);

  final ValueNotifier<List<List<Offset>>> ink;
  final List<PixelRect> hits;

  @override
  void paint(Canvas canvas, Size size) {
    final highlight = Paint()..color = const Color(0x66FFB300);
    for (final hit in hits) {
      canvas.drawRect(
        Rect.fromLTRB(
          hit.left * size.width / 10000,
          hit.top * size.height / 10000,
          hit.right * size.width / 10000,
          hit.bottom * size.height / 10000,
        ),
        highlight,
      );
    }
    final pen = Paint()
      ..color = const Color(0xFF194CB7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in ink.value) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1, pen);
      } else {
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (final point in stroke.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, pen);
      }
    }
  }

  @override
  bool shouldRepaint(_Overlay oldDelegate) => oldDelegate.hits != hits;
}
