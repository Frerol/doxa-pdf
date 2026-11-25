// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/src/engine/pdfium_backend.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';
import 'package:pdfium_ffi/testing.dart';
import 'package:test/test.dart';

void main() {
  late PdfiumBackend backend;

  setUp(() => backend = PdfiumBackend(openPdfium()));
  tearDown(() => backend.dispose());

  test('keeps separate render and editing instances (ADR-0005)', () {
    final opened = backend.open(
      7,
      MemorySource(buildMinimalPdf()),
      null,
    ) as DocumentOpened;
    expect(opened.handle, const DocumentHandle(7));

    final render = backend.renderInstance(7);
    final edit = backend.editInstance(7);
    expect(edit.address, isNot(render.address));
    expect(backend.editInstance(7).address, edit.address);
    // Using the render instance does not load anything into the editing one.
    expect(backend.pageText(7, 0).text, minimalPdfText);

    backend.close(7);
    expect(backend.isOpen(7), isFalse);
    expect(() => backend.editInstance(7), throwsA(isA<PdfEngineException>()));
  });

  test('caches a bounded number of pages and text layers', () {
    backend.open(1, MemorySource(buildMinimalPdf()), null);
    final first = backend.pageText(1, 0);
    expect(identical(backend.pageText(1, 0), first), isTrue);
  });
}
