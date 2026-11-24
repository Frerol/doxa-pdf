// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

/// Lines of text drawn on every test page (Helvetica 14 pt, from y = 700).
const testLines = [
  'The quick brown fox jumps over the lazy dog.',
  'Studying with a pen: highlight, underline and squiggly.',
  'Annotations must survive a round trip to other readers.',
  'Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
];

/// A Letter page (612 x 792 pt) with [testLines], optionally rotated, with a
/// non-zero CropBox origin, or with a "foreign" Text annotation that carries
/// an unknown key (/Foo) which must survive our edits.
Uint8List buildTestPdf({
  int rotate = 0,
  List<num>? cropBox,
  bool foreignAnnot = false,
}) {
  final content = StringBuffer('BT /F1 14 Tf 72 700 Td 18 TL\n');
  for (final line in testLines) {
    content.write('($line) Tj T*\n');
  }
  content.write('ET\n');
  final c = content.toString();

  final page = StringBuffer(
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
    '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R',
  );
  if (rotate != 0) page.write(' /Rotate $rotate');
  if (cropBox != null) page.write(' /CropBox [${cropBox.join(' ')}]');
  if (foreignAnnot) page.write(' /Annots [6 0 R]');
  page.write(' >>');

  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    page.toString(),
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding >>',
    '<< /Length ${c.length} >>\nstream\n${c}endstream',
    if (foreignAnnot)
      '<< /Type /Annot /Subtype /Text /Rect [500 620 524 644] '
          '/Contents (Note from another app) /NM (foreign-1) /T (Okular) '
          '/C [1 0.5 0] /F 4 /Foo (bar) /Name /Comment >>',
  ];
  final out = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R '
    '/ID [<0123456789abcdef0123456789abcdef> <0123456789abcdef0123456789abcdef>] >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(out.toString()));
}
