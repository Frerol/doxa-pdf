// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:doxa_core/doxa_core.dart';

import '../api/pdf_engine.dart';
import '../api/types.dart';
import '../text/text_search.dart';

/// One page of a [FakeDocument].
final class FakePage {
  const FakePage({
    this.width = 612,
    this.height = 792,
    this.rotation = 0,
    this.text = '',
    this.label,
    this.links = const [],
    this.annotations = const [],
  });

  /// Displayed size in points.
  final double width;
  final double height;
  final int rotation;

  /// Page text. Char `i` gets a 10 × 12 pt box on one line, in order.
  final String text;
  final String? label;
  final List<PageLink> links;

  /// Returned by `annotations`, as they are.
  final List<Annotation> annotations;
}

/// A document served by [FakePdfEngine].
final class FakeDocument {
  const FakeDocument({
    required this.pages,
    this.password,
    this.outline = const [],
    this.metadata = const DocumentMetadata(),
  });

  final List<FakePage> pages;

  /// When set, `open` needs this password (FR-FILE-003).
  final String? password;
  final List<OutlineNode> outline;
  final DocumentMetadata metadata;
}

/// In-memory [PdfEngine] for widget and controller tests, with no native
/// code. Open sources must be [FileSource]s whose path is a key of
/// [documents].
///
/// Renders are solid fills whose grey level depends on the page index. They
/// complete in order after [renderDelay]; [renderLog] records every request
/// that was rendered, so tests can check what the UI asked for.
final class FakePdfEngine implements PdfEngine {
  FakePdfEngine(this.documents, {this.renderDelay = Duration.zero});

  final Map<String, FakeDocument> documents;
  final Duration renderDelay;

  final renderLog = <RenderRequest>[];
  final _open = <int, FakeDocument>{};

  /// Annotations per open document and page, once changed.
  final _edited = <int, Map<int, List<Annotation>>>{};
  final _generations = <int, int>{};
  var _nextId = 1;
  var _disposed = false;

  /// Documents currently open; for tests.
  int get openDocumentCount => _open.length;

  @override
  Future<OpenResult> open(DocumentSource source, {String? password}) async {
    _checkAlive();
    final key = switch (source) {
      FileSource(:final path) => path,
      MemorySource() => null,
    };
    final document = documents[key];
    if (document == null) return const OpenFailed(OpenFailure.file);
    if (document.password != null && document.password != password) {
      return password == null
          ? const PasswordRequired()
          : const WrongPassword();
    }
    final handle = DocumentHandle(_nextId++);
    _open[handle.id] = document;
    final sizes = Float64List(document.pages.length * 2);
    for (final (i, page) in document.pages.indexed) {
      sizes[i * 2] = page.width;
      sizes[i * 2 + 1] = page.height;
    }
    return DocumentOpened(
      handle,
      DocumentInfo(
        pageSizes: sizes,
        pageLabels: [for (final page in document.pages) page.label],
        metadata: document.metadata,
      ),
    );
  }

  @override
  Future<void> close(DocumentHandle document) async {
    _open.remove(document.id);
    _edited.remove(document.id);
    _generations.remove(document.id);
  }

  @override
  Future<PageDetails> pageDetails(DocumentHandle document, int index) async {
    final page = _page(document, index);
    final rotated = page.rotation == 90 || page.rotation == 270;
    return PageDetails(
      pageIndex: index,
      cropBox: PdfRect(
        0,
        0,
        rotated ? page.height : page.width,
        rotated ? page.width : page.height,
      ),
      rotation: page.rotation,
    );
  }

  @override
  Future<List<OutlineNode>> outline(DocumentHandle document) async =>
      _document(document).outline;

  @override
  Future<List<PageLink>> pageLinks(DocumentHandle document, int index) async =>
      _page(document, index).links;

  /// Annotations change in memory, per open document, as the PDFium engine
  /// changes them in its editing instance; nothing is checked beyond ids.
  @override
  Future<List<Annotation>> annotations(
    DocumentHandle document,
    int index,
  ) async => List.unmodifiable(_annotationsOf(document, index));

  List<Annotation> _annotationsOf(DocumentHandle document, int index) {
    final page = _page(document, index);
    return (_edited[document.id] ??= {})[index] ??= [...page.annotations];
  }

  @override
  Future<void> addAnnotations(
    DocumentHandle document,
    List<Annotation> annotations,
  ) async {
    for (final annotation in annotations) {
      final list = _annotationsOf(document, annotation.pageIndex);
      if (list.any((a) => a.id == annotation.id)) {
        throw PdfEngineException(
          EngineErrorKind.unsupportedEdit,
          'Already on page ${annotation.pageIndex}: ${annotation.id}',
        );
      }
      list.add(annotation);
    }
  }

  @override
  Future<Annotation> updateAnnotation(
    DocumentHandle document,
    Annotation annotation,
  ) async {
    final list = _annotationsOf(document, annotation.pageIndex);
    final index = list.indexWhere((a) => a.id == annotation.id);
    if (index < 0) {
      throw PdfEngineException(
        EngineErrorKind.unknownAnnotation,
        'Not on page ${annotation.pageIndex}: ${annotation.id}',
      );
    }
    return list[index] = annotation;
  }

  @override
  Future<void> deleteAnnotations(
    DocumentHandle document,
    int pageIndex,
    List<String> ids,
  ) async {
    final list = _annotationsOf(document, pageIndex);
    for (final id in ids) {
      if (!list.any((a) => a.id == id)) {
        throw PdfEngineException(
          EngineErrorKind.unknownAnnotation,
          'Not on page $pageIndex: $id',
        );
      }
    }
    list.removeWhere((a) => ids.contains(a.id));
  }

  @override
  Future<PageText> pageText(DocumentHandle document, int index) async =>
      _text(index, _page(document, index));

  @override
  Future<RenderResult> render(
    RenderRequest request, {
    CancelToken? cancel,
  }) async {
    _page(request.document, request.pageIndex);
    await Future<void>.delayed(renderDelay);
    if (!_open.containsKey(request.document.id)) {
      return const RenderSkipped(SkipReason.closed);
    }
    if (cancel?.isCancelled ?? false) {
      return const RenderSkipped(SkipReason.cancelled);
    }
    if (!request.priority.keptWhenStale &&
        request.generation < (_generations[request.document.id] ?? 0)) {
      return const RenderSkipped(SkipReason.stale);
    }
    renderLog.add(request);
    final grey = 255 - (request.pageIndex * 37) % 128;
    final pixels = Uint8List(request.width * request.height * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels
        ..[i] = grey
        ..[i + 1] = grey
        ..[i + 2] = grey
        ..[i + 3] = 255;
    }
    return RenderedBitmap(request.width, request.height, pixels);
  }

  @override
  void setGeneration(DocumentHandle document, int generation) {
    final current = _generations[document.id] ?? 0;
    if (generation > current) _generations[document.id] = generation;
  }

  @override
  Stream<SearchHit> search(DocumentHandle document, SearchQuery query) async* {
    final pages = _document(document).pages;
    final matcher = TextMatcher(query);
    if (matcher.isEmpty) return;
    for (final (i, page) in pages.indexed) {
      await Future<void>.delayed(Duration.zero);
      if (!_open.containsKey(document.id)) return;
      yield* Stream.fromIterable(matcher.findAll(_text(i, page)));
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _open.clear();
  }

  static PageText _text(int index, FakePage page) {
    final units = page.text.length;
    final boxes = Float64List(units * 4);
    for (var i = 0; i < units; i++) {
      boxes
        ..[i * 4] = 72 + i * 10
        ..[i * 4 + 1] = 700
        ..[i * 4 + 2] = 82 + i * 10
        ..[i * 4 + 3] = 712;
    }
    return PageText(
      pageIndex: index,
      text: page.text,
      charIndexOfUnit: Int32List.fromList(List.generate(units, (i) => i)),
      charBoxes: boxes,
    );
  }

  FakeDocument _document(DocumentHandle handle) {
    _checkAlive();
    final document = _open[handle.id];
    if (document == null) {
      throw PdfEngineException(
        EngineErrorKind.unknownDocument,
        'Not open: ${handle.id}',
      );
    }
    return document;
  }

  FakePage _page(DocumentHandle handle, int index) {
    final pages = _document(handle).pages;
    if (index < 0 || index >= pages.length) {
      throw PdfEngineException(
        EngineErrorKind.invalidPage,
        'Page $index is outside 0..${pages.length - 1}',
      );
    }
    return pages[index];
  }

  void _checkAlive() {
    if (_disposed) {
      throw const PdfEngineException(EngineErrorKind.stopped, 'Disposed');
    }
  }
}
