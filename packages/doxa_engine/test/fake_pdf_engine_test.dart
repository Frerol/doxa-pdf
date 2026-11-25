// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/testing.dart';
import 'package:test/test.dart';

void main() {
  FakePdfEngine engine() => FakePdfEngine({
    'book.pdf': const FakeDocument(
      pages: [
        FakePage(text: 'Ação e reação', label: 'i'),
        FakePage(width: 792, height: 612, rotation: 90, text: 'acao'),
      ],
      outline: [OutlineNode(title: 'Start')],
    ),
    'secret.pdf': const FakeDocument(pages: [FakePage()], password: 'study'),
  });

  test('opens documents and reports their pages', () async {
    final fake = engine();
    final opened =
        await fake.open(const FileSource('book.pdf')) as DocumentOpened;
    expect(opened.info.pageCount, 2);
    expect(opened.info.pageLabels, ['i', null]);
    expect(opened.info.pageSize(1), (width: 792.0, height: 612.0));
    final details = await fake.pageDetails(opened.handle, 1);
    expect(details.rotation, 90);
    expect(details.transform().viewSize, (792.0, 612.0));
    expect((await fake.outline(opened.handle)).single.title, 'Start');
    expect(await fake.open(const FileSource('missing.pdf')), isA<OpenFailed>());
  });

  test('checks passwords', () async {
    final fake = engine();
    const source = FileSource('secret.pdf');
    expect(await fake.open(source), isA<PasswordRequired>());
    expect(await fake.open(source, password: 'x'), isA<WrongPassword>());
    expect(await fake.open(source, password: 'study'), isA<DocumentOpened>());
  });

  test('renders solid fills and logs requests', () async {
    final fake = engine();
    final doc = (await fake.open(
      const FileSource('book.pdf'),
    ) as DocumentOpened).handle;
    RenderRequest request({int generation = 0}) => RenderRequest(
      document: doc,
      pageIndex: 0,
      scale: 1,
      x: 0,
      y: 0,
      width: 2,
      height: 2,
      generation: generation,
    );
    final bitmap = await fake.render(request()) as RenderedBitmap;
    expect(bitmap.pixels, hasLength(16));
    expect(bitmap.pixels[3], 255);
    fake.setGeneration(doc, 1);
    expect(await fake.render(request()), isA<RenderSkipped>());
    expect(await fake.render(request(generation: 1)), isA<RenderedBitmap>());
    expect(fake.renderLog, hasLength(2));
    await fake.close(doc);
    expect(() => fake.pageText(doc, 0), throwsA(isA<PdfEngineException>()));
  });

  test('searches with the real matcher', () async {
    final fake = engine();
    final doc = (await fake.open(
      const FileSource('book.pdf'),
    ) as DocumentOpened).handle;
    final hits = await fake.search(doc, const SearchQuery('acao')).toList();
    // "reação" contains "acao" too.
    expect(hits.map((h) => (h.pageIndex, h.charIndex)), [
      (0, 0),
      (0, 9),
      (1, 0),
    ]);
    expect(hits.first.rects.single.left, 72);
  });
}
