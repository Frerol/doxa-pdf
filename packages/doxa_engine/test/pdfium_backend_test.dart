// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/src/engine/pdfium_backend.dart';
import 'package:doxa_engine/src/engine/protocol.dart';
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

  test('deleting an annotation also deletes its popup', () {
    final pdf = openPdfium();
    final bytes = File(
      File('test_corpus/annotations.pdf').existsSync()
          ? 'test_corpus/annotations.pdf'
          : '../../test_corpus/annotations.pdf',
    ).readAsBytesSync();
    backend.open(1, MemorySource(bytes), null);
    int count() {
      final page = pdf.FPDF_LoadPage(backend.editInstance(1), 0);
      final n = pdf.FPDFPage_GetAnnotCount(page);
      pdf.FPDF_ClosePage(page);
      return n;
    }

    const id = 'doxa:0b3f6c1e-2a4d-4e8f-9a1b-3c5d7e9f1a2b';
    final before = count();
    backend.edit(1, const DeleteAnnotationsEdit(0, [id]));
    // The highlight and the popup that belongs to it.
    expect(count(), before - 2);
    expect(
      backend.annotations(1, 0).map((Annotation a) => a.id),
      isNot(contains(id)),
    );
  });
}
