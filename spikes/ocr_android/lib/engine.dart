// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

import 'text_layer.dart';

typedef Raster = ({int width, int height, TransferableTypedData data});
typedef PixelRect = ({int left, int top, int right, int bottom});
typedef SearchHit = ({int page, List<PixelRect> rectangles});

double elapsedMs(Stopwatch watch) => watch.elapsedMicroseconds / 1000;

class Engine {
  Engine._(this._port);

  final SendPort _port;

  static Future<Engine> start() async {
    final ready = ReceivePort();
    try {
      await Isolate.spawn(_serve, ready.sendPort, debugName: 'pdfium-engine');
      final response = await ready.first;
      if (response is SendPort) return Engine._(response);
      throw StateError(response.toString());
    } finally {
      ready.close();
    }
  }

  Future<T> call<T>(String command, [List<Object> args = const []]) async {
    final reply = ReceivePort();
    try {
      _port.send((command, args, reply.sendPort));
      final (value, error) = await reply.first as (Object?, String?);
      if (error != null) throw StateError(error);
      return value as T;
    } finally {
      reply.close();
    }
  }
}

void _serve(SendPort ready) {
  try {
    final engine = _PdfEngine();
    final inbox = ReceivePort();
    ready.send(inbox.sendPort);
    inbox.listen((message) {
      final (command, args, reply) =
          message as (String, List<Object>, SendPort);
      try {
        reply.send((engine.dispatch(command, args), null));
        if (command == 'shutdown') inbox.close();
      } catch (error) {
        reply.send((null, error.toString()));
      }
    });
  } catch (error) {
    ready.send(error.toString());
  }
}

class _PdfEngine {
  _PdfEngine() {
    pdf.FPDF_InitLibrary();
  }

  final pdf = openPdfium();
  Pointer<fpdf_document_t__> source = nullptr;
  Pointer<fpdf_document_t__> edit = nullptr;
  final written = <int, int>{};

  Object? dispatch(String command, List<Object> args) => switch (command) {
    'open' => open(args[0] as String),
    'begin' => begin(args[0] as String),
    'preview' => raster(args[0] as int, gray: false),
    'raster' => raster(args[0] as int, gray: true),
    'write' => write(
      args[0] as int,
      args[1] as int,
      args[2] as int,
      (args[3] as List<Object?>).cast<Map<Object?, Object?>>(),
    ),
    'save' => savePending(args[0] as String),
    'abort' => abort(),
    'search' => search(args[0] as String, args[1] as String),
    'shutdown' => shutdown(),
    _ => throw ArgumentError.value(command),
  };

  Pointer<fpdf_document_t__> load(String path) => using((arena) {
    final doc = pdf.FPDF_LoadDocument(
      path.toNativeUtf8(allocator: arena).cast(),
      nullptr,
    );
    require(
      doc != nullptr,
      'Cannot open PDF (error ${pdf.FPDF_GetLastError()})',
    );
    return doc;
  });

  int open(String path) {
    final next = load(path);
    final count = pdf.FPDF_GetPageCount(next);
    if (count <= 0) {
      pdf.FPDF_CloseDocument(next);
      throw StateError('The PDF has no pages');
    }
    if (source != nullptr) pdf.FPDF_CloseDocument(source);
    source = next;
    return count;
  }

  Null begin(String path) {
    abort();
    edit = load(path);
    return null;
  }

  Null abort() {
    if (edit != nullptr) pdf.FPDF_CloseDocument(edit);
    edit = nullptr;
    written.clear();
    return null;
  }

  Null shutdown() {
    abort();
    if (source != nullptr) pdf.FPDF_CloseDocument(source);
    pdf.FPDF_DestroyLibrary();
    return null;
  }

  T withPage<T>(
    Pointer<fpdf_document_t__> doc,
    int index,
    T Function(Pointer<fpdf_page_t__>) action,
  ) {
    final page = pdf.FPDF_LoadPage(doc, index);
    require(page != nullptr, 'Cannot load page ${index + 1}');
    try {
      return action(page);
    } finally {
      pdf.FPDF_ClosePage(page);
    }
  }

  T withText<T>(
    Pointer<fpdf_page_t__> page,
    T Function(Pointer<fpdf_textpage_t__>) action,
  ) {
    final text = pdf.FPDFText_LoadPage(page);
    require(text != nullptr, 'Cannot load page text');
    try {
      return action(text);
    } finally {
      pdf.FPDFText_ClosePage(text);
    }
  }

  Raster raster(int index, {required bool gray}) =>
      withPage(source, index, (page) {
        final pointsWide = pdf.FPDF_GetPageWidthF(page);
        final pointsHigh = pdf.FPDF_GetPageHeightF(page);
        final scale = gray ? 300 / 72 : 1000 / pointsWide;
        final width = (pointsWide * scale).round();
        final height = (pointsHigh * scale).round();
        require(
          width > 0 && height > 0 && width * height <= 40 * 1000 * 1000,
          'Raster dimensions exceed the lab limit',
        );
        final stride = gray ? (width + 3) & ~3 : width * 4;
        final bytes = malloc<Uint8>(stride * height);
        try {
          final bitmap = pdf.FPDFBitmap_CreateEx(
            width,
            height,
            gray ? FPDFBitmap_Gray : FPDFBitmap_BGRA,
            bytes.cast(),
            stride,
          );
          require(bitmap != nullptr, 'Cannot allocate PDFium bitmap');
          try {
            pdf.FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF);
            // OCR reads page content. Previews also show foreign annotations.
            pdf.FPDF_RenderPageBitmap(
              bitmap,
              page,
              0,
              0,
              width,
              height,
              0,
              gray ? FPDF_GRAYSCALE : FPDF_ANNOT,
            );
            final pixels = bytes.asTypedList(stride * height);
            if (!gray || width == stride) {
              return (
                width: width,
                height: height,
                data: TransferableTypedData.fromList([pixels]),
              );
            }
            final packed = Uint8List(width * height);
            for (var y = 0; y < height; y++) {
              packed.setRange(y * width, (y + 1) * width, pixels, y * stride);
            }
            return (
              width: width,
              height: height,
              data: TransferableTypedData.fromList([packed]),
            );
          } finally {
            pdf.FPDFBitmap_Destroy(bitmap);
          }
        } finally {
          malloc.free(bytes);
        }
      });

  int write(
    int index,
    int width,
    int height,
    List<Map<Object?, Object?>> words,
  ) => withPage(edit, index, (page) {
    require(
      pdf.FPDFPage_GetRotation(page) == 0,
      'Rotated OCR pages are unsupported',
    );
    require(
      withText(page, pdf.FPDFText_CountChars) == 0,
      'Page ${index + 1} already contains text',
    );
    final inserted = <({String text, Box box})>[];
    addWords(pdf, edit, page, words, width, height, inserted);
    written[index] = inserted.length;
    return inserted.length;
  });

  ({double saveMs, double verifyMs}) savePending(String path) {
    final watch = Stopwatch()..start();
    save(pdf, edit, File(path));
    final saveMs = elapsedMs(watch);
    watch.reset();
    final check = load(path);
    try {
      require(
        pdf.FPDF_GetPageCount(check) == pdf.FPDF_GetPageCount(edit),
        'Page count changed after save',
      );
      for (final MapEntry(key: index, value: count) in written.entries) {
        withPage(check, index, (page) {
          require(
            withText(page, pdf.FPDFText_CountChars) >= count,
            'Saved text missing on page ${index + 1}',
          );
        });
      }
    } finally {
      pdf.FPDF_CloseDocument(check);
    }
    return (saveMs: saveMs, verifyMs: elapsedMs(watch));
  }

  List<SearchHit> search(String path, String query) {
    final doc = load(path);
    try {
      return [
        for (var index = 0; index < pdf.FPDF_GetPageCount(doc); index++)
          ...withPage(
            doc,
            index,
            (page) => withText(
              page,
              (text) => using((arena) {
                final find = pdf.FPDFText_FindStart(
                  text,
                  query.toNativeUtf16(allocator: arena).cast(),
                  0,
                  0,
                );
                require(find != nullptr, 'Cannot start search');
                try {
                  final hits = <SearchHit>[];
                  final edges = arena<Double>(4);
                  final a = arena<Int>(2);
                  final b = arena<Int>(2);
                  while (pdf.FPDFText_FindNext(find) != 0) {
                    final count = pdf.FPDFText_CountRects(
                      text,
                      pdf.FPDFText_GetSchResultIndex(find),
                      pdf.FPDFText_GetSchCount(find),
                    );
                    final rectangles = <PixelRect>[];
                    for (var i = 0; i < count; i++) {
                      require(
                        pdf.FPDFText_GetRect(
                              text,
                              i,
                              edges,
                              edges + 1,
                              edges + 2,
                              edges + 3,
                            ) !=
                            0,
                        'Cannot load match bounds',
                      );
                      require(
                        pdf.FPDF_PageToDevice(
                                  page,
                                  0,
                                  0,
                                  10000,
                                  10000,
                                  0,
                                  edges[0],
                                  edges[1],
                                  a,
                                  a + 1,
                                ) !=
                                0 &&
                            pdf.FPDF_PageToDevice(
                                  page,
                                  0,
                                  0,
                                  10000,
                                  10000,
                                  0,
                                  edges[2],
                                  edges[3],
                                  b,
                                  b + 1,
                                ) !=
                                0,
                        'Cannot map match bounds',
                      );
                      rectangles.add((
                        left: a[0],
                        top: a[1],
                        right: b[0],
                        bottom: b[1],
                      ));
                    }
                    hits.add((page: index, rectangles: rectangles));
                  }
                  return hits;
                } finally {
                  pdf.FPDFText_FindClose(find);
                }
              }),
            ),
          ),
      ];
    } finally {
      pdf.FPDF_CloseDocument(doc);
    }
  }
}
