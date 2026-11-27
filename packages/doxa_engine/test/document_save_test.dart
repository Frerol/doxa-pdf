// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/src/engine/document_saver.dart';
import 'package:doxa_engine/src/engine/pdfium_backend.dart';
import 'package:doxa_engine/src/engine/protocol.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';
import 'package:test/test.dart';

String corpus(String name) {
  for (final dir in ['test_corpus', '../../test_corpus']) {
    final file = File('$dir/$name');
    if (file.existsSync()) return file.absolute.path;
  }
  throw StateError('Missing test_corpus/$name');
}

TextMarkup _highlight(int page) => TextMarkup(
  id: DoxaMarker.newId(),
  pageIndex: page,
  kind: MarkupKind.highlight,
  quads: [PdfQuad.fromRect(const PdfRect(72, 698, 328, 714))],
  text: 'A field notebook',
  color: 0xFFFF00,
  opacity: 0.4,
  byDoxa: true,
);

void main() {
  late PdfiumBackend backend;
  late Directory dir;
  var nextId = 1;

  setUp(() {
    backend = PdfiumBackend(openPdfium());
    dir = Directory.systemTemp.createTempSync('doxa-save-');
  });
  tearDown(() {
    backend.dispose();
    dir.deleteSync(recursive: true);
  });

  /// Copies a corpus file into the temp folder and opens it from there.
  (int, File) openCopy(String name) {
    final file = File(corpus(name)).copySync('${dir.path}/$name');
    final id = nextId++;
    expect(
      backend.open(id, FileSource(file.path), null),
      isA<DocumentOpened>(),
    );
    return (id, file);
  }

  List<String> filesInDir() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  group('saving (FR-SAVE-002, ADR-0008)', () {
    test(
      'a saved copy reopens with the changes; the original is untouched',
      () {
        final (doc, original) = openCopy('annotations.pdf');
        final before = original.readAsBytesSync();
        final added = _highlight(1);
        backend.edit(doc, AddAnnotationsEdit([added]));
        backend.edit(doc, const DeleteAnnotationsEdit(0, ['square-1']));

        final copy = '${dir.path}/copy.pdf';
        final result = backend.save(doc, copy);
        expect(result, isA<Saved>());
        expect((result as Saved).bytes, File(copy).lengthSync());
        expect(original.readAsBytesSync(), before);

        final reopened = nextId++;
        backend.open(reopened, FileSource(copy), null);
        expect(
          backend.annotations(reopened, 1).map((a) => a.id),
          contains(added.id),
        );
        expect(
          backend.annotations(reopened, 0).map((a) => a.id),
          isNot(contains('square-1')),
        );
        // Untouched foreign annotations keep their values.
        expect(
          backend
              .annotations(reopened, 0)
              .where((a) => a.id == 'other-app-ink'),
          backend.annotations(doc, 0).where((a) => a.id == 'other-app-ink'),
        );
        expect(filesInDir(), ['annotations.pdf', 'copy.pdf']);
      },
    );

    test('saving over the open file replaces it, and the document keeps '
        'rendering and reading from the new file', () {
      final (doc, file) = openCopy('annotations.pdf');
      final added = _highlight(0);
      backend.edit(doc, AddAnnotationsEdit([added]));
      expect(backend.save(doc, file.path), isA<Saved>());
      expect(filesInDir(), ['annotations.pdf']);

      final pixels = backend.render(
        RenderRequest(
          document: DocumentHandle(doc),
          pageIndex: 0,
          scale: 0.25,
          x: 0,
          y: 0,
          width: 64,
          height: 64,
          generation: 0,
          priority: RenderPriority.visibleTile,
        ),
      );
      expect(pixels.width, 64);
      expect(backend.pageText(doc, 0).text, contains('field notebook'));

      final reopened = nextId++;
      backend.open(reopened, FileSource(file.path), null);
      expect(
        backend.annotations(reopened, 0).map((a) => a.id),
        contains(added.id),
      );
      // A second save after another change works the same way.
      backend.edit(doc, DeleteAnnotationsEdit(0, [added.id]));
      expect(backend.save(doc, file.path), isA<Saved>());
    });

    test('a file with cross-reference streams stays valid', () {
      final (doc, file) = openCopy('annotated-acrobat.pdf');
      final highlight = backend.annotations(doc, 0).single;
      backend.edit(doc, AddAnnotationsEdit([_highlight(0)]));
      expect(backend.save(doc, file.path), isA<Saved>());

      final reopened = nextId++;
      backend.open(reopened, FileSource(file.path), null);
      final read = backend.annotations(reopened, 0);
      expect(read, hasLength(2));
      // Acrobat's own highlight comes back as it was.
      expect(read.firstWhere((a) => a.id == highlight.id), highlight);
    });

    for (final step in SaveStep.values) {
      test('a failure while ${step.name} leaves the original as it was', () {
        final (doc, file) = openCopy('annotations.pdf');
        final before = file.readAsBytesSync();
        backend.edit(doc, AddAnnotationsEdit([_highlight(0)]));
        backend.saver.fault = (at) {
          if (at == step) throw const FileSystemException('injected');
        };
        final result = backend.save(doc, file.path);
        expect(result, isA<SaveFailed>());
        expect((result as SaveFailed).reason, switch (step) {
          SaveStep.write => SaveFailure.writeFailed,
          SaveStep.verify => SaveFailure.verifyFailed,
          SaveStep.replace => SaveFailure.cannotReplace,
        });
        expect(file.readAsBytesSync(), before);
        expect(filesInDir(), ['annotations.pdf']);

        // The changes are still there: the next save writes them.
        backend.saver.fault = null;
        expect(backend.save(doc, file.path), isA<Saved>());
        expect(file.readAsBytesSync(), isNot(before));
      });
    }

    test('a full disk is reported as such', () {
      final (doc, _) = openCopy('annotations.pdf');
      backend.saver.fault = (at) {
        if (at == SaveStep.write) {
          throw const FileSystemException('full', '', OSError('', 28));
        }
      };
      final result = backend.save(doc, '${dir.path}/copy.pdf');
      expect((result as SaveFailed).reason, SaveFailure.noSpace);
    });

    test('a target folder that does not exist fails without changes', () {
      final (doc, _) = openCopy('annotations.pdf');
      final result = backend.save(doc, '${dir.path}/missing/copy.pdf');
      expect((result as SaveFailed).reason, SaveFailure.writeFailed);
      expect(filesInDir(), ['annotations.pdf']);
    });

    test('an unsigned document has no signatures', () {
      final (doc, _) = openCopy('annotations.pdf');
      expect(backend.signatureCount(doc), 0);
    });
  });
}
