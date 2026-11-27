// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:isolate';
import 'dart:typed_data';

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_engine/src/engine/backend.dart';
import 'package:doxa_engine/src/engine/engine_host.dart';
import 'package:doxa_engine/src/engine/protocol.dart';
import 'package:test/test.dart';

/// Records what reaches the backend, as PDFium would see it.
final class RecordingBackend implements EngineBackend {
  RecordingBackend({this.pages = 3, this.pageTexts = const {}});

  final int pages;
  final Map<int, String> pageTexts;
  final rendered = <RenderRequest>[];
  final textCalls = <int>[];
  final failingPages = <int>{};
  final openIds = <int>{};
  var disposed = false;

  @override
  OpenResult open(int documentId, DocumentSource source, String? password) {
    openIds.add(documentId);
    return DocumentOpened(
      DocumentHandle(documentId),
      DocumentInfo(
        pageSizes: Float64List(pages * 2),
        pageLabels: List.filled(pages, null),
        metadata: const DocumentMetadata(),
      ),
    );
  }

  @override
  bool isOpen(int documentId) => openIds.contains(documentId);
  @override
  int pageCount(int documentId) => pages;
  @override
  void close(int documentId) => openIds.remove(documentId);

  @override
  PageDetails pageDetails(int documentId, int pageIndex) => PageDetails(
    pageIndex: pageIndex,
    cropBox: const PdfRect(0, 0, 612, 792),
    rotation: 0,
  );

  @override
  List<OutlineNode> outline(int documentId) => const [];
  @override
  List<PageLink> pageLinks(int documentId, int pageIndex) => const [];

  @override
  List<Annotation> annotations(int documentId, int pageIndex) => const [];

  @override
  Annotation? edit(int documentId, AnnotationEdit edit) => null;

  @override
  SaveResult save(int documentId, String path) => const Saved(0);

  @override
  int signatureCount(int documentId) => 0;

  @override
  PageText pageText(int documentId, int pageIndex) {
    textCalls.add(pageIndex);
    if (failingPages.contains(pageIndex)) {
      throw const PdfEngineException(EngineErrorKind.documentError, 'broken');
    }
    final text = pageTexts[pageIndex] ?? '';
    return PageText(
      pageIndex: pageIndex,
      text: text,
      charIndexOfUnit: Int32List.fromList(List.generate(text.length, (i) => i)),
      charBoxes: Float64List(text.length * 4),
    );
  }

  @override
  RenderedPixels render(RenderRequest request) {
    if (failingPages.contains(request.pageIndex)) {
      throw StateError('native failure');
    }
    rendered.add(request);
    return RenderedPixels(
      request.width,
      request.height,
      TransferableTypedData.fromList([Uint8List(4)]),
    );
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  late RecordingBackend backend;
  late EngineHost host;
  late List<EngineReply> replies;
  var nextId = 100;

  Future<void> settle() async {
    for (var i = 0; i < 50 && host.pendingJobs > 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);
  }

  Future<DocumentHandle> openDocument() async {
    host.handle(OpenCommand(1, MemorySource(Uint8List(0)), null));
    await settle();
    final reply = replies.removeLast() as ValueReply;
    return (reply.value! as DocumentOpened).handle;
  }

  int render(
    DocumentHandle doc, {
    int page = 0,
    RenderPriority priority = RenderPriority.visibleTile,
    int generation = 0,
    int x = 0,
  }) {
    final id = nextId++;
    host.handle(
      RenderCommand(
        id,
        RenderRequest(
          document: doc,
          pageIndex: page,
          scale: 1,
          x: x,
          y: 0,
          width: 16,
          height: 16,
          priority: priority,
          generation: generation,
        ),
      ),
    );
    return id;
  }

  Map<int, Object> outcomes() => {
    for (final reply in replies)
      reply.id: switch (reply) {
        RenderReply() => 'rendered',
        SkippedReply(:final reason) => reason,
        ErrorReply(:final kind) => kind,
        _ => reply.runtimeType,
      },
  };

  setUp(() {
    backend = RecordingBackend(pageTexts: {0: 'no hit', 1: 'Ação', 2: 'acao'});
    replies = [];
    host = EngineHost(backend, replies.add);
  });

  test('runs renders by priority', () async {
    final doc = await openDocument();
    render(doc, priority: RenderPriority.background, x: 1);
    render(doc, priority: RenderPriority.thumbnail, x: 2);
    render(doc, priority: RenderPriority.nearTile, x: 3);
    render(doc, priority: RenderPriority.nearPreview, x: 4);
    render(doc, priority: RenderPriority.visibleTile, x: 5);
    render(doc, priority: RenderPriority.visiblePreview, x: 6);
    render(doc, priority: RenderPriority.visibleTile, x: 7);
    await settle();
    expect(backend.rendered.map((r) => r.x), [6, 5, 7, 4, 3, 2, 1]);
  });

  test('runs the newest generation first within a priority', () async {
    final doc = await openDocument();
    render(doc, priority: RenderPriority.thumbnail, x: 1);
    host.handle(GenerationCommand(doc.id, 1));
    render(doc, priority: RenderPriority.thumbnail, generation: 1, x: 2);
    await settle();
    expect(backend.rendered.map((r) => r.x), [2, 1]);
  });

  test('a cancelled generation never reaches the backend', () async {
    final doc = await openDocument();
    final stale = [
      for (var i = 0; i < 20; i++) render(doc, x: i, generation: 0),
    ];
    final preview = render(doc, priority: RenderPriority.visiblePreview);
    final thumbnail = render(doc, priority: RenderPriority.thumbnail);
    host.handle(GenerationCommand(doc.id, 1));
    final current = render(doc, generation: 1, x: 99);
    final old = render(doc, generation: 0, x: 42);
    await settle();

    expect(backend.rendered.map((r) => r.generation).toSet(), {0, 1});
    expect(
      backend.rendered.where((r) => r.generation == 0).map((r) => r.priority),
      everyElement(
        isIn([RenderPriority.visiblePreview, RenderPriority.thumbnail]),
      ),
    );
    final result = outcomes();
    for (final id in [...stale, old]) {
      expect(result[id], SkipReason.stale, reason: 'request $id');
    }
    expect(result[preview], 'rendered');
    expect(result[thumbnail], 'rendered');
    expect(result[current], 'rendered');
  });

  test('cancel drops a queued render', () async {
    final doc = await openDocument();
    final id = render(doc);
    host.handle(CancelCommand(id));
    await settle();
    expect(backend.rendered, isEmpty);
    expect(outcomes()[id], SkipReason.cancelled);
  });

  test('close skips pending renders and frees the document', () async {
    final doc = await openDocument();
    final id = render(doc);
    host.handle(CloseCommand(2, doc.id));
    await settle();
    expect(backend.rendered, isEmpty);
    expect(outcomes()[id], SkipReason.closed);
    expect(backend.isOpen(doc.id), isFalse);
    expect(outcomes()[2], ValueReply);

    final after = render(doc);
    await settle();
    expect(outcomes()[after], EngineErrorKind.unknownDocument);
  });

  test('a failing job becomes an error reply and the engine goes on', () async {
    final doc = await openDocument();
    backend.failingPages.add(1);
    final bad = render(doc, page: 1);
    final good = render(doc, page: 2);
    final outside = render(doc, page: 7);
    host.handle(QueryCommand(3, QueryKind.pageText, doc.id, -1));
    await settle();
    final result = outcomes();
    expect(result[bad], EngineErrorKind.internal);
    expect(result[good], 'rendered');
    expect(result[outside], EngineErrorKind.invalidPage);
    expect(result[3], EngineErrorKind.invalidPage);
  });

  test('search streams hits page by page and skips damaged pages', () async {
    final doc = await openDocument();
    backend.failingPages.add(0);
    host.handle(SearchCommand(5, doc.id, const SearchQuery('acao')));
    await settle();
    final hits = [
      for (final reply in replies)
        if (reply case SearchHitsReply(:final hits)) ...hits,
    ];
    expect(hits.map((h) => h.pageIndex), [1, 2]);
    expect(replies.last, isA<SearchDoneReply>());
    expect(backend.textCalls, [0, 1, 2]);
  });

  test('renders wait behind a search page only one job at a time', () async {
    final doc = await openDocument();
    host.handle(SearchCommand(5, doc.id, const SearchQuery('acao')));
    final id = render(doc);
    await settle();
    // The visible tile ran before any later search page.
    final order = [
      for (final reply in replies)
        if (reply is RenderReply)
          'render'
        else if (reply is SearchHitsReply)
          'hits ${reply.hits.first.pageIndex}',
    ];
    expect(order.first, 'render');
    expect(outcomes()[id], 'rendered');
  });

  test('closing a document ends its search with an error', () async {
    final doc = await openDocument();
    host.handle(SearchCommand(5, doc.id, const SearchQuery('acao')));
    host.handle(CloseCommand(6, doc.id));
    await settle();
    expect(outcomes()[5], EngineErrorKind.unknownDocument);
    expect(replies.whereType<SearchDoneReply>(), isEmpty);
  });

  test('cancelling a search stops it', () async {
    final doc = await openDocument();
    host.handle(SearchCommand(5, doc.id, const SearchQuery('acao')));
    host.handle(const CancelCommand(5));
    await settle();
    expect(backend.textCalls, isEmpty);
    expect(replies.whereType<SearchHitsReply>(), isEmpty);
  });

  test('shutdown disposes the backend and refuses later commands', () async {
    final doc = await openDocument();
    final id = render(doc);
    host.handle(const ShutdownCommand(9));
    render(doc);
    await settle();
    expect(backend.disposed, isTrue);
    expect(backend.rendered, isEmpty);
    expect(outcomes()[id], SkipReason.closed);
    expect(replies.last, isA<ErrorReply>());
  });
}
