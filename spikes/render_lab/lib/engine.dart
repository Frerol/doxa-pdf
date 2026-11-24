// SPDX-License-Identifier: GPL-3.0-or-later
//
// Render Lab engine (Spike A, issue #5): one long-lived isolate owns PDFium.
// Requests carry a priority and a viewport generation; stale tile requests
// are dropped so the queue always serves what is on screen now.
// Throwaway prototype.

import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

/// Priorities: lower is more urgent.
const priVisiblePreview = 0,
    priVisibleTile = 1,
    priNearPreview = 2,
    priNearTile = 3;

class EngineClient {
  EngineClient._(this._send, this.replies);
  final SendPort _send;
  final Stream<Map<String, Object?>> replies;

  static Future<EngineClient> spawn() async {
    final rx = ReceivePort();
    await Isolate.spawn(_main, rx.sendPort, debugName: 'pdfium-engine');
    final stream = rx.asBroadcastStream();
    final send = await stream.first as SendPort;
    return EngineClient._(send, stream.cast<Map<String, Object?>>());
  }

  void open(String path) => _send.send({'op': 'open', 'path': path});
  void generation(int gen) => _send.send({'op': 'gen', 'gen': gen});
  void render(Map<String, Object?> request) =>
      _send.send({'op': 'render', ...request});
}

// ---------------------------------------------------------------------------
// Isolate side

late final PdfiumBindings _pdf;
Pointer<fpdf_document_t__> _doc = nullptr;
final _pages =
    LinkedHashMap<int, Pointer<fpdf_page_t__>>(); // LRU of loaded pages
final _queue = <Map<String, Object?>>[];
var _gen = 0;
var _pumping = false;
late SendPort _out;

void _main(SendPort out) {
  _out = out;
  _pdf = openPdfium();
  final config = calloc<FPDF_LIBRARY_CONFIG_>()..ref.version = 2;
  _pdf.FPDF_InitLibraryWithConfig(config);
  final rx = ReceivePort();
  out.send(rx.sendPort);
  rx.listen((m) {
    final msg = m as Map<String, Object?>;
    switch (msg['op']) {
      case 'open':
        _open(msg['path']! as String);
      case 'gen':
        _gen = msg['gen']! as int;
        final dropped = <int>[];
        _queue.removeWhere((r) {
          final stale =
              (r['gen']! as int) < _gen &&
              (r['pri']! as int) != priVisiblePreview;
          if (stale) dropped.add(r['id']! as int);
          return stale;
        });
        if (dropped.isNotEmpty) _out.send({'op': 'dropped', 'ids': dropped});
      case 'render':
        _queue.add(msg);
        _schedule();
    }
  });
}

void _schedule() {
  if (_pumping) return;
  _pumping = true;
  // Timer.run yields to the event loop between jobs, so new priorities and
  // generation updates arrive before the next job is chosen.
  Timer.run(_pump);
}

void _pump() {
  _pumping = false;
  if (_queue.isEmpty) return;
  var best = 0;
  for (var i = 1; i < _queue.length; i++) {
    final a = _queue[i], b = _queue[best];
    final pa = a['pri']! as int, pb = b['pri']! as int;
    if (pa < pb || (pa == pb && (a['gen']! as int) > (b['gen']! as int)))
      best = i;
  }
  _renderJob(_queue.removeAt(best));
  if (_queue.isNotEmpty) _schedule();
}

void _open(String path) {
  final sw = Stopwatch()..start();
  for (final p in _pages.values) {
    _pdf.FPDF_ClosePage(p);
  }
  _pages.clear();
  _queue.clear();
  if (_doc != nullptr) _pdf.FPDF_CloseDocument(_doc);
  final p = path.toNativeUtf8().cast<Char>();
  _doc = _pdf.FPDF_LoadDocument(p, nullptr);
  calloc.free(p);
  if (_doc == nullptr) {
    _out.send({
      'op': 'error',
      'message': 'load failed ${_pdf.FPDF_GetLastError()}',
    });
    return;
  }
  final n = _pdf.FPDF_GetPageCount(_doc);
  final sizes = Float64List(n * 2);
  final s = calloc<FS_SIZEF_>();
  for (var i = 0; i < n; i++) {
    _pdf.FPDF_GetPageSizeByIndexF(_doc, i, s);
    sizes[i * 2] = s.ref.width;
    sizes[i * 2 + 1] = s.ref.height;
  }
  calloc.free(s);
  _out.send({
    'op': 'opened',
    'pages': n,
    'sizes': sizes,
    'openMs': sw.elapsedMicroseconds / 1000,
  });
}

Pointer<fpdf_page_t__> _page(int index) {
  final cached = _pages.remove(index);
  if (cached != null) return _pages[index] = cached;
  final page = _pdf.FPDF_LoadPage(_doc, index);
  _pages[index] = page;
  if (_pages.length > 8) {
    final oldest = _pages.keys.first;
    _pdf.FPDF_ClosePage(_pages.remove(oldest)!);
  }
  return page;
}

void _renderJob(Map<String, Object?> r) {
  final sw = Stopwatch()..start();
  final w = r['w']! as int, h = r['h']! as int;
  final page = _page(r['page']! as int);
  final buf = malloc<Uint8>(w * h * 4);
  final bmp = _pdf.FPDFBitmap_CreateEx(
    w,
    h,
    FPDFBitmap_BGRA,
    buf.cast(),
    w * 4,
  );
  _pdf.FPDFBitmap_FillRect(bmp, 0, 0, w, h, 0xFFFFFFFF);
  final m = calloc<FS_MATRIX_>();
  final scale = r['scale']! as double;
  m.ref
    ..a = scale
    ..d = scale
    ..e = -(r['x']! as int).toDouble()
    ..f = -(r['y']! as int).toDouble();
  final clip = calloc<FS_RECTF_>();
  clip.ref
    ..right = w.toDouble()
    ..bottom = h.toDouble();
  // Annotations off: Doxa draws its own; foreign ones would come from a
  // separate read-only instance (see docs/spikes/A-rendering.md).
  _pdf.FPDF_RenderPageBitmapWithMatrix(
    bmp,
    page,
    m,
    clip,
    FPDF_REVERSE_BYTE_ORDER,
  );
  _pdf.FPDFBitmap_Destroy(bmp);
  calloc
    ..free(m)
    ..free(clip);
  final data = TransferableTypedData.fromList([buf.asTypedList(w * h * 4)]);
  malloc.free(buf);
  _out.send({
    'op': 'tile',
    'id': r['id'],
    'data': data,
    'w': w,
    'h': h,
    'ms': sw.elapsedMicroseconds / 1000,
    'queue': _queue.length,
  });
}
