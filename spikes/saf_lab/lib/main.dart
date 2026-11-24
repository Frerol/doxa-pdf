// SPDX-License-Identifier: GPL-3.0-or-later
//
// SAF Lab — throwaway prototype for Spike C (issue #7), part 2.
// Pick a PDF through the system picker, add an ink annotation with PDFium,
// full-save to a temp file and write it back through the content URI.

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: SafLab()),
);

const _channel = MethodChannel('saf_lab');

class SafLab extends StatefulWidget {
  const SafLab({super.key});

  @override
  State<SafLab> createState() => _SafLabState();
}

class _SafLabState extends State<SafLab> {
  Map<Object?, Object?>? picked;
  final log = <String>[];
  bool busy = false;

  void _log(String line) {
    debugPrint('SAFLAB $line');
    setState(() => log.add(line));
  }

  Future<void> _pick() async {
    final r = await _channel.invokeMapMethod<Object?, Object?>('pick');
    if (r == null) return;
    setState(() => picked = r);
    _log(
      'picked name=${r['name']} size=${r['size']} authority=${r['authority']} '
      'supportsWrite=${r['supportsWrite']} persisted=${r['persisted']}',
    );
  }

  Future<void> _annotateAndSave() async {
    final p = picked;
    if (p == null) return;
    setState(() => busy = true);
    try {
      final uri = p['uri']! as String;
      final tmp = Directory.systemTemp.path;
      final input = '$tmp/input.pdf', output = '$tmp/output.pdf';

      final copy = (await _channel.invokeMapMethod<String, Object?>('copyIn', {
        'uri': uri,
        'path': input,
      }))!;
      _log('copyIn ${copy['ms']}ms ${_mb(copy['bytes']! as int)}');

      final r = await Isolate.run(_annotateJob(input, output));
      _log(
        'pdfium load=${r.loadMs}ms annotate=${r.annotMs}ms save=${r.saveMs}ms '
        'annots ${r.before}->${r.after} out=${_mb(r.bytes)}',
      );

      final wb = (await _channel.invokeMapMethod<String, Object?>('writeBack', {
        'uri': uri,
        'path': output,
      }))!;
      _log(
        'writeBack ${wb['ms']}ms verified=${wb['verified']} '
        'size=${_mb(wb['bytes']! as int)}',
      );

      // Re-read through SAF and reopen with PDFium.
      await _channel.invokeMapMethod('copyIn', {'uri': uri, 'path': input});
      final count = await Isolate.run(_countJob(input));
      _log('reopen via SAF: page 1 has $count annotations');
    } on PlatformException catch (e) {
      _log('ERROR ${e.message}');
    } catch (e) {
      _log('ERROR $e');
    } finally {
      setState(() => busy = false);
    }
  }

  static String _mb(int b) => '${(b / 1048576).toStringAsFixed(2)}MB';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SAF Lab (Spike C)')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: busy ? null : _pick,
            child: const Text('1. Escolher PDF'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy || picked == null ? null : _annotateAndSave,
            child: Text(
              busy ? 'Trabalhando…' : '2. Anotar e salvar no arquivo',
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                for (final l in log)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// PDFium work (runs in a short-lived isolate)

// Top-level factories so the closures sent to Isolate.run capture only the
// path strings, not the State or the async context.
_Result Function() _annotateJob(String input, String output) =>
    () => _annotate(input, output);
int Function() _countJob(String input) => () => _countAnnots(input);

typedef _Result = ({
  int loadMs,
  int annotMs,
  int saveMs,
  int before,
  int after,
  int bytes,
});

late PdfiumBindings _pdf;
RandomAccessFile? _out;

int _writeBlock(Pointer<FPDF_FILEWRITE_> self, Pointer<Void> data, int size) {
  _out!.writeFromSync(data.cast<Uint8>().asTypedList(size));
  return 1;
}

Pointer<fpdf_document_t__> _open(String path) {
  _pdf = openPdfium();
  final config = calloc<FPDF_LIBRARY_CONFIG_>()..ref.version = 2;
  _pdf.FPDF_InitLibraryWithConfig(config);
  calloc.free(config);
  final p = path.toNativeUtf8().cast<Char>();
  final doc = _pdf.FPDF_LoadDocument(p, nullptr);
  calloc.free(p);
  if (doc == nullptr)
    throw StateError('PDFium error ${_pdf.FPDF_GetLastError()}');
  return doc;
}

int _countAnnots(String path) {
  final doc = _open(path);
  final page = _pdf.FPDF_LoadPage(doc, 0);
  final n = _pdf.FPDFPage_GetAnnotCount(page);
  _pdf.FPDF_ClosePage(page);
  _pdf.FPDF_CloseDocument(doc);
  _pdf.FPDF_DestroyLibrary();
  return n;
}

_Result _annotate(String input, String output) {
  final sw = Stopwatch()..start();
  final doc = _open(input);
  final loadMs = sw.elapsedMilliseconds;
  final page = _pdf.FPDF_LoadPage(doc, 0);
  final before = _pdf.FPDFPage_GetAnnotCount(page);
  final h = _pdf.FPDF_GetPageHeightF(page);

  // A small check-mark scribble near the top-left corner of page 1.
  final a = _pdf.FPDFPage_CreateAnnot(page, FPDF_ANNOT_INK);
  final pts = [
    for (var i = 0; i <= 40; i++)
      (40.0 + i * 1.5, h - 60 - 12 * math.sin(i / 6)),
  ];
  final ink = calloc<FS_POINTF_>(pts.length);
  for (var i = 0; i < pts.length; i++) {
    ink[i]
      ..x = pts[i].$1
      ..y = pts[i].$2;
  }
  _pdf.FPDFAnnot_AddInkStroke(a, ink, pts.length);
  calloc.free(ink);
  final rect = calloc<FS_RECTF_>();
  rect.ref
    ..left = 35
    ..right = 105
    ..top = h - 40
    ..bottom = h - 80;
  _pdf.FPDFAnnot_SetRect(a, rect);
  calloc.free(rect);
  _pdf.FPDFAnnot_SetColor(
    a,
    FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
    198,
    40,
    40,
    255,
  );
  _pdf.FPDFAnnot_SetFlags(a, FPDF_ANNOT_FLAG_PRINT);
  final path = _pdf.FPDFPageObj_CreateNewPath(pts.first.$1, pts.first.$2);
  for (final p in pts.skip(1)) {
    _pdf.FPDFPath_LineTo(path, p.$1, p.$2);
  }
  for (final p in pts.reversed) {
    _pdf.FPDFPath_LineTo(path, p.$1, p.$2 - 2.5);
  }
  _pdf.FPDFPath_Close(path);
  _pdf.FPDFPath_SetDrawMode(path, FPDF_FILLMODE_WINDING, 0);
  _pdf.FPDFPageObj_SetFillColor(path, 198, 40, 40, 255);
  _pdf.FPDFAnnot_AppendObject(a, path); // last: see Spike C findings
  _pdf.FPDFPage_CloseAnnot(a);
  final after = _pdf.FPDFPage_GetAnnotCount(page);
  _pdf.FPDF_ClosePage(page);
  final annotMs = sw.elapsedMilliseconds - loadMs;

  // Full save streamed to a temp file.
  final t0 = sw.elapsedMilliseconds;
  _out = File(output).openSync(mode: FileMode.write);
  final cb =
      NativeCallable<
        Int Function(Pointer<FPDF_FILEWRITE_>, Pointer<Void>, UnsignedLong)
      >.isolateLocal(_writeBlock, exceptionalReturn: 0);
  final fw = calloc<FPDF_FILEWRITE_>()
    ..ref.version = 1
    ..ref.WriteBlock = cb.nativeFunction;
  final ok = _pdf.FPDF_SaveAsCopy(doc, fw, 0);
  _out!.closeSync();
  calloc.free(fw);
  cb.close();
  if (ok == 0) throw StateError('FPDF_SaveAsCopy failed');
  final saveMs = sw.elapsedMilliseconds - t0;

  _pdf.FPDF_CloseDocument(doc);
  _pdf.FPDF_DestroyLibrary();
  return (
    loadMs: loadMs,
    annotMs: annotMs,
    saveMs: saveMs,
    before: before,
    after: after,
    bytes: File(output).lengthSync(),
  );
}
