// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

typedef Box = ({double left, double bottom, double right, double top});

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Box objectBounds(
  PdfiumBindings pdf,
  Pointer<fpdf_pageobject_t__> object,
  Arena arena,
) {
  final edges = arena<Float>(4);
  require(
    pdf.FPDFPageObj_GetBounds(object, edges, edges + 1, edges + 2, edges + 3) !=
        0,
    'Cannot measure text object',
  );
  return (left: edges[0], bottom: edges[1], right: edges[2], top: edges[3]);
}

void addWords(
  PdfiumBindings pdf,
  Pointer<fpdf_document_t__> doc,
  Pointer<fpdf_page_t__> page,
  List<Map<Object?, Object?>> results,
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
      for (final result in results) {
        final text = result['text']! as String;
        final left = result['left']! as int;
        final top = result['top']! as int;
        final wordWidth = (result['right']! as int) - left;
        final wordHeight = (result['bottom']! as int) - top;
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
              () => objectBounds(pdf, object, scratch),
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
      if (words.isEmpty) return;
      require(
        pdf.FPDFPage_GenerateContent(page) != 0,
        'Cannot generate content',
      );
    } finally {
      pdf.FPDFFont_Close(font);
    }
  });
}

void save(PdfiumBindings pdf, Pointer<fpdf_document_t__> doc, File target) {
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
