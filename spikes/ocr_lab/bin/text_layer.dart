// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

typedef Box = ({double left, double bottom, double right, double top});

late final PdfiumBindings pdf;

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void withDocument(
  String path,
  void Function(Pointer<fpdf_document_t__>) action,
) {
  using((arena) {
    final doc = pdf.FPDF_LoadDocument(
      path.toNativeUtf8(allocator: arena).cast(),
      nullptr,
    );
    require(doc != nullptr, 'Cannot open $path');
    try {
      action(doc);
    } finally {
      pdf.FPDF_CloseDocument(doc);
    }
  });
}

Box objectBounds(Pointer<fpdf_pageobject_t__> object, Arena arena) {
  final edges = arena<Float>(4);
  require(
    pdf.FPDFPageObj_GetBounds(object, edges, edges + 1, edges + 2, edges + 3) !=
        0,
    'Cannot measure text object',
  );
  return (left: edges[0], bottom: edges[1], right: edges[2], top: edges[3]);
}

void addWords(
  Pointer<fpdf_document_t__> doc,
  Pointer<fpdf_page_t__> page,
  File tsv,
  int width,
  int height,
  List<({String text, Box box})> words,
) {
  final measured = <String, Box>{};
  using((arena) {
    final font = pdf.FPDFText_LoadStandardFont(
      doc,
      'Helvetica'.toNativeUtf8(allocator: arena).cast(),
    );
    require(font != nullptr, 'Cannot load Helvetica');
    try {
      final origin = arena<Double>(2);
      require(
        pdf.FPDF_DeviceToPage(
              page,
              0,
              0,
              width,
              height,
              0,
              0,
              height,
              origin,
              origin + 1,
            ) !=
            0,
        'Cannot map raster coordinates',
      );
      final sx = pdf.FPDF_GetPageWidthF(page) / width;
      final sy = pdf.FPDF_GetPageHeightF(page) / height;
      for (final row in tsv.readAsLinesSync().skip(1)) {
        final fields = row.split('\t');
        if (fields.first != '5') continue;
        final text = fields.skip(11).join('\t').trim();
        if (text.isEmpty) continue;
        final left = int.parse(fields[6]);
        final top = int.parse(fields[7]);
        final wordWidth = int.parse(fields[8]);
        final wordHeight = int.parse(fields[9]);
        require(wordWidth > 0 && wordHeight > 0, 'Empty word box: $row');
        final box = (
          left: origin[0] + left * sx,
          right: origin[0] + (left + wordWidth) * sx,
          bottom: origin[1] + (height - top - wordHeight) * sy,
          top: origin[1] + (height - top) * sy,
        );
        using((scratch) {
          final object = pdf.FPDFPageObj_CreateTextObj(doc, font, 12);
          require(object != nullptr, 'Cannot create text object');
          var inserted = false;
          try {
            require(
              pdf.FPDFText_SetText(
                    object,
                    text.toNativeUtf16(allocator: scratch).cast(),
                  ) !=
                  0,
              'Helvetica cannot encode "$text"',
            );
            require(
              pdf.FPDFTextObj_SetTextRenderMode(
                    object,
                    FPDF_TEXT_RENDERMODE.FPDF_TEXTRENDERMODE_INVISIBLE,
                  ) !=
                  0,
              'Cannot set invisible render mode',
            );
            final natural = measured.putIfAbsent(
              text,
              () => objectBounds(object, scratch),
            );
            final scaleX =
                (box.right - box.left) / (natural.right - natural.left);
            final scaleY =
                (box.top - box.bottom) / (natural.top - natural.bottom);
            require(
              scaleX.isFinite && scaleY.isFinite && scaleX > 0 && scaleY > 0,
              'Degenerate text bounds for "$text"',
            );
            pdf.FPDFPageObj_Transform(
              object,
              scaleX,
              0,
              0,
              scaleY,
              box.left - natural.left * scaleX,
              box.bottom - natural.bottom * scaleY,
            );
            pdf.FPDFPage_InsertObject(page, object);
            inserted = true;
            words.add((text: text, box: box));
          } finally {
            if (!inserted) pdf.FPDFPageObj_Destroy(object);
          }
        });
      }
      require(words.isNotEmpty, 'No OCR words on page');
      require(
        pdf.FPDFPage_GenerateContent(page) != 0,
        'Cannot generate content',
      );
    } finally {
      pdf.FPDFFont_Close(font);
    }
  });
}

void save(Pointer<fpdf_document_t__> doc, File target) {
  final file = target.openSync(mode: FileMode.write);
  try {
    final callback =
        NativeCallable<
          Int Function(Pointer<FPDF_FILEWRITE_>, Pointer<Void>, UnsignedLong)
        >.isolateLocal((
          Pointer<FPDF_FILEWRITE_> _,
          Pointer<Void> data,
          int size,
        ) {
          file.writeFromSync(data.cast<Uint8>().asTypedList(size));
          return 1;
        }, exceptionalReturn: 0);
    try {
      using((arena) {
        final writer = arena<FPDF_FILEWRITE_>()
          ..ref.version = 1
          ..ref.WriteBlock = callback.nativeFunction;
        require(pdf.FPDF_SaveAsCopy(doc, writer, 0) != 0, 'Full save failed');
      });
    } finally {
      callback.close();
    }
  } finally {
    file.closeSync();
  }
}

Box union(Box a, Box b) => (
  left: math.min(a.left, b.left),
  right: math.max(a.right, b.right),
  bottom: math.min(a.bottom, b.bottom),
  top: math.max(a.top, b.top),
);

List<double> offsets(Box a, Box b) => [
  (a.left - b.left).abs(),
  (a.right - b.right).abs(),
  (a.bottom - b.bottom).abs(),
  (a.top - b.top).abs(),
];

String stats(List<double> errors) =>
    'mean=${(errors.reduce((a, b) => a + b) / errors.length).toStringAsFixed(5)} '
    'max=${errors.reduce(math.max).toStringAsFixed(5)} pt';

void verify(Pointer<fpdf_page_t__> page, List<({String text, Box box})> words) {
  final textPage = pdf.FPDFText_LoadPage(page);
  require(textPage != nullptr, 'Cannot load saved text page');
  try {
    using((arena) {
      final indices = <Pointer<fpdf_pageobject_t__>, List<int>>{};
      for (var i = 0; i < pdf.FPDFText_CountChars(textPage); i++) {
        final object = pdf.FPDFText_GetTextObject(textPage, i);
        if (object != nullptr) {
          indices.putIfAbsent(object, () => []).add(i);
        }
      }

      final hits = <String, Set<int>>{};
      final charErrors = <double>[];
      final selectionErrors = <double>[];
      final edges = arena<Double>(4);
      Box readBox() =>
          (left: edges[0], bottom: edges[1], right: edges[2], top: edges[3]);
      var found = 0;
      final first = pdf.FPDFPage_CountObjects(page) - words.length;
      require(first >= 0, 'Missing text objects');
      for (var i = 0; i < words.length; i++) {
        final word = words[i];
        final object = pdf.FPDFPage_GetObject(page, first + i);
        final chars = indices[object];
        require(
          chars != null && chars.isNotEmpty,
          'No characters for "${word.text}"',
        );
        final start = chars!.first;
        final count = chars.last - start + 1;
        final matches = hits.putIfAbsent(
          word.text,
          () => using((scratch) {
            final search = pdf.FPDFText_FindStart(
              textPage,
              word.text.toNativeUtf16(allocator: scratch).cast(),
              FPDF_MATCHCASE,
              0,
            );
            require(search != nullptr, 'Cannot start search');
            try {
              final starts = <int>{};
              while (pdf.FPDFText_FindNext(search) != 0) {
                if (pdf.FPDFText_GetSchCount(search) == word.text.length) {
                  starts.add(pdf.FPDFText_GetSchResultIndex(search));
                }
              }
              return starts;
            } finally {
              pdf.FPDFText_FindClose(search);
            }
          }),
        );
        if (matches.contains(start)) {
          found++;
        } else {
          final hyphen = chars.any(
            (index) => pdf.FPDFText_IsHyphen(textPage, index) != 0,
          );
          stdout.writeln('Search miss: ${word.text} (PDFium hyphen: $hyphen)');
          require(hyphen && word.text.endsWith('-'), 'Unexpected search miss');
        }

        Box? charBox;
        for (final index in chars) {
          require(
            pdf.FPDFText_GetCharBox(
                  textPage,
                  index,
                  edges,
                  edges + 2,
                  edges + 1,
                  edges + 3,
                ) !=
                0,
            'Cannot read character box',
          );
          charBox = charBox == null ? readBox() : union(charBox, readBox());
        }

        Box? selection;
        final rectangles = pdf.FPDFText_CountRects(textPage, start, count);
        for (var rect = 0; rect < rectangles; rect++) {
          require(
            pdf.FPDFText_GetRect(
                  textPage,
                  rect,
                  edges,
                  edges + 3,
                  edges + 2,
                  edges + 1,
                ) !=
                0,
            'Cannot read selection rectangle',
          );
          selection = selection == null
              ? readBox()
              : union(selection, readBox());
        }
        require(selection != null, 'No selection for "${word.text}"');
        charErrors.addAll(offsets(charBox!, word.box));
        selectionErrors.addAll(offsets(selection!, word.box));
      }
      stdout.writeln('Search $found/${words.length}');
      stdout.writeln('Character-box union ${stats(charErrors)}');
      stdout.writeln('Selection-box union ${stats(selectionErrors)}');
      require(
        selectionErrors.reduce(math.max) < 0.01,
        'Selection alignment regression',
      );
    });
  } finally {
    pdf.FPDFText_ClosePage(textPage);
  }
}

void main(List<String> args) {
  if (args.length < 6 || (args.length - 2) % 4 != 0) {
    stderr.writeln('Usage: text_layer INPUT OUTPUT (PAGE WIDTH HEIGHT TSV)+');
    exitCode = 64;
    return;
  }
  final target = File(args[1]).absolute;
  require(!target.existsSync(), 'Output already exists: ${target.path}');
  final tmpDir = target.parent.createTempSync('.ocr-save-');
  try {
    pdf = openPdfium();
    pdf.FPDF_InitLibrary();
    try {
      final pages = <int, List<({String text, Box box})>>{};
      final pending = File('${tmpDir.path}/output.pdf');
      withDocument(args[0], (doc) {
        final write = Stopwatch()..start();
        for (var i = 2; i < args.length; i += 4) {
          final index = int.parse(args[i]) - 1;
          require(!pages.containsKey(index), 'Duplicate page: ${index + 1}');
          final page = pdf.FPDF_LoadPage(doc, index);
          require(page != nullptr, 'Cannot load page ${index + 1}');
          try {
            require(pdf.FPDFPage_GetRotation(page) == 0, 'Rotated input page');
            final textPage = pdf.FPDFText_LoadPage(page);
            require(textPage != nullptr, 'Cannot inspect source text');
            final count = pdf.FPDFText_CountChars(textPage);
            pdf.FPDFText_ClosePage(textPage);
            require(count == 0, 'Source already contains text');
            addWords(
              doc,
              page,
              File(args[i + 3]),
              int.parse(args[i + 1]),
              int.parse(args[i + 2]),
              pages[index] = [],
            );
          } finally {
            pdf.FPDF_ClosePage(page);
          }
        }
        write.stop();
        final saveTime = Stopwatch()..start();
        save(doc, pending);
        saveTime.stop();
        stdout.writeln(
          'Write ${write.elapsedMicroseconds / 1000} ms, '
          'full save ${saveTime.elapsedMicroseconds / 1000} ms',
        );
      });
      withDocument(pending.path, (doc) {
        for (final entry in pages.entries) {
          final page = pdf.FPDF_LoadPage(doc, entry.key);
          require(page != nullptr, 'Cannot reopen page ${entry.key + 1}');
          try {
            stdout.writeln('Page ${entry.key + 1}');
            verify(page, entry.value);
          } finally {
            pdf.FPDF_ClosePage(page);
          }
        }
      });
      pending.renameSync(target.path);
    } finally {
      pdf.FPDF_DestroyLibrary();
    }
  } finally {
    tmpDir.deleteSync(recursive: true);
  }
}
