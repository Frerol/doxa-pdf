// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

/// Text drawn by [buildMinimalPdf].
const minimalPdfText = 'Hello Doxa';

/// Page size of [buildMinimalPdf], in PDF points.
const minimalPdfPageSize = 200;

/// Builds a small, valid single-page PDF (200 × 200 pt) for tests and
/// diagnostics, so no binary fixture has to be committed.
///
/// The page shows [minimalPdfText] in Helvetica near the top and a black
/// 80 × 80 pt square whose lower-left corner is at (60, 20).
Uint8List buildMinimalPdf() {
  const content =
      'BT /F1 18 Tf 40 160 Td ($minimalPdfText) Tj ET\n'
      '0 0 0 rg 60 20 80 80 re f\n';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 $minimalPdfPageSize $minimalPdfPageSize] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding >>',
    '<< /Length ${content.length} >>\nstream\n${content}endstream',
  ];

  final out = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  // The document is pure ASCII, so string offsets equal byte offsets.
  return Uint8List.fromList(ascii.encode(out.toString()));
}
