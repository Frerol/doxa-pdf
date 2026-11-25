// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_engine/doxa_engine.dart';
import 'package:pdfium_ffi/testing.dart';
import 'package:test/test.dart';

void main() {
  test('only one engine runs at a time', () async {
    final engine = await PdfiumEngine.spawn();
    await expectLater(PdfiumEngine.spawn(), throwsStateError);
    await engine.dispose();

    final next = await PdfiumEngine.spawn();
    final opened = await next.open(MemorySource(buildMinimalPdf()));
    expect(opened, isA<DocumentOpened>());
    await next.dispose();
  });

  test('a disposed engine refuses calls and ends searches', () async {
    final engine = await PdfiumEngine.spawn();
    final opened =
        await engine.open(MemorySource(buildMinimalPdf())) as DocumentOpened;
    await engine.dispose();
    await engine.dispose(); // No-op.
    final stopped = isA<PdfEngineException>().having(
      (e) => e.kind,
      'kind',
      EngineErrorKind.stopped,
    );
    await expectLater(
      engine.open(MemorySource(buildMinimalPdf())),
      throwsA(stopped),
    );
    await expectLater(
      engine.search(opened.handle, const SearchQuery('Doxa')).toList(),
      throwsA(stopped),
    );
  });
}
