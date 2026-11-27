// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import '../api/types.dart';
import '../text/text_search.dart';
import 'backend.dart';
import 'protocol.dart';

/// Runs inside the engine isolate: queues commands by priority, drops stale
/// and cancelled renders before they reach the backend, and turns every
/// failure into a reply, so one bad document never stops the engine.
///
/// Jobs run one per event-loop turn, so cancellations and new generations
/// that arrive meanwhile are applied before the next job is chosen.
final class EngineHost {
  EngineHost(this.backend, this.reply);

  final EngineBackend backend;
  final void Function(EngineReply reply) reply;

  final _queue = <_Job>[];
  final _generations = <int, int>{};
  var _nextDocumentId = 1;
  var _sequence = 0;
  var _scheduled = false;
  var _stopped = false;

  /// Jobs waiting to run; for tests.
  int get pendingJobs => _queue.length;

  void handle(EngineCommand command) {
    if (_stopped) {
      reply(ErrorReply(command.id, EngineErrorKind.stopped, 'Engine stopped'));
      return;
    }
    switch (command) {
      case OpenCommand(:final id, :final source, :final password):
        _enqueue(_Job(id, _Rank.control, () => _open(id, source, password)));
      case CloseCommand(:final id, :final documentId):
        _close(id, documentId);
      case QueryCommand():
        _enqueue(
          _Job(
            command.id,
            _Rank.control,
            () => _query(command),
            documentId: command.documentId,
          ),
        );
      case EditCommand(:final id, :final documentId, :final edit):
        _enqueue(
          _Job(id, _Rank.control, () {
            _checkOpen(documentId);
            reply(ValueReply(id, backend.edit(documentId, edit)));
          }, documentId: documentId),
        );
      case RenderCommand(:final id, :final request):
        _addRender(id, request);
      case SearchCommand(:final id, :final documentId, :final query):
        _startSearch(id, documentId, query);
      case CancelCommand(:final id):
        _cancel(id);
      case GenerationCommand(:final documentId, :final generation):
        _setGeneration(documentId, generation);
      case ShutdownCommand(:final id):
        _shutdown(id);
    }
  }

  // --- Scheduling ---------------------------------------------------------

  void _enqueue(_Job job) {
    job.sequence = _sequence++;
    _queue.add(job);
    _schedule();
  }

  void _schedule() {
    if (_scheduled || _queue.isEmpty) return;
    _scheduled = true;
    Timer.run(_runNext);
  }

  void _runNext() {
    _scheduled = false;
    if (_stopped || _queue.isEmpty) return;
    var best = 0;
    for (var i = 1; i < _queue.length; i++) {
      if (_queue[i].isBefore(_queue[best])) best = i;
    }
    final job = _queue.removeAt(best);
    try {
      job.run();
    } on PdfEngineException catch (e) {
      job.fail(this, e.kind, e.message);
    } catch (e) {
      job.fail(this, EngineErrorKind.internal, '$e');
    }
    _schedule();
  }

  // --- Commands -----------------------------------------------------------

  void _open(int id, DocumentSource source, String? password) {
    final documentId = _nextDocumentId++;
    final result = backend.open(documentId, source, password);
    reply(ValueReply(id, result));
  }

  void _close(int id, int documentId) {
    _queue.removeWhere((job) {
      if (job.documentId != documentId) return false;
      job.dropForClose(this);
      return true;
    });
    _generations.remove(documentId);
    try {
      if (backend.isOpen(documentId)) backend.close(documentId);
      reply(ValueReply(id, null));
    } catch (e) {
      reply(ErrorReply(id, EngineErrorKind.internal, '$e'));
    }
  }

  void _query(QueryCommand command) {
    final doc = command.documentId;
    _checkOpen(doc);
    final page = command.pageIndex;
    final Object value = switch (command.kind) {
      QueryKind.pageDetails => backend.pageDetails(doc, _checkPage(doc, page)),
      QueryKind.outline => backend.outline(doc),
      QueryKind.pageLinks => backend.pageLinks(doc, _checkPage(doc, page)),
      QueryKind.pageText => backend.pageText(doc, _checkPage(doc, page)),
      QueryKind.annotations => backend.annotations(doc, _checkPage(doc, page)),
    };
    reply(ValueReply(command.id, value));
  }

  void _addRender(int id, RenderRequest request) {
    final doc = request.document.id;
    if (!backend.isOpen(doc)) {
      reply(ErrorReply(id, EngineErrorKind.unknownDocument, 'Not open: $doc'));
      return;
    }
    if (_isStale(request)) {
      reply(SkippedReply(id, SkipReason.stale));
      return;
    }
    _enqueue(
      _Job(
        id,
        _Rank.render(request.priority),
        () {
          _checkPage(doc, request.pageIndex);
          reply(RenderReply(id, backend.render(request)));
        },
        documentId: doc,
        render: request,
      ),
    );
  }

  bool _isStale(RenderRequest request) =>
      !request.priority.keptWhenStale &&
      request.generation < (_generations[request.document.id] ?? 0);

  void _setGeneration(int documentId, int generation) {
    final current = _generations[documentId] ?? 0;
    if (generation <= current) return;
    _generations[documentId] = generation;
    _queue.removeWhere((job) {
      final render = job.render;
      if (render == null || !_isStale(render)) return false;
      reply(SkippedReply(job.id, SkipReason.stale));
      return true;
    });
  }

  void _cancel(int id) {
    _queue.removeWhere((job) {
      if (job.id != id) return false;
      if (job.render != null) reply(SkippedReply(id, SkipReason.cancelled));
      return true;
    });
  }

  void _startSearch(int id, int documentId, SearchQuery query) {
    if (!backend.isOpen(documentId)) {
      reply(
        ErrorReply(
          id,
          EngineErrorKind.unknownDocument,
          'Not open: $documentId',
        ),
      );
      return;
    }
    final matcher = TextMatcher(query);
    if (matcher.isEmpty) {
      reply(SearchDoneReply(id));
      return;
    }
    _enqueueSearchPage(id, documentId, matcher, 0);
  }

  void _enqueueSearchPage(int id, int doc, TextMatcher matcher, int page) {
    _enqueue(
      _Job(
        id,
        _Rank.search,
        () {
          final pageCount = backend.pageCount(doc);
          if (page >= pageCount) {
            reply(SearchDoneReply(id));
            return;
          }
          try {
            final hits = matcher.findAll(backend.pageText(doc, page));
            if (hits.isNotEmpty) reply(SearchHitsReply(id, hits));
          } on PdfEngineException catch (e) {
            // A damaged page must not end the search of the others.
            if (e.kind != EngineErrorKind.documentError) rethrow;
          }
          if (page + 1 < pageCount) {
            _enqueueSearchPage(id, doc, matcher, page + 1);
          } else {
            reply(SearchDoneReply(id));
          }
        },
        documentId: doc,
        isSearch: true,
      ),
    );
  }

  void _shutdown(int id) {
    _stopped = true;
    for (final job in _queue) {
      job.dropForClose(this, shutdown: true);
    }
    _queue.clear();
    try {
      backend.dispose();
    } finally {
      reply(ValueReply(id, null));
    }
  }

  void _checkOpen(int documentId) {
    if (!backend.isOpen(documentId)) {
      throw PdfEngineException(
        EngineErrorKind.unknownDocument,
        'Not open: $documentId',
      );
    }
  }

  int _checkPage(int documentId, int? pageIndex) {
    _checkOpen(documentId);
    final count = backend.pageCount(documentId);
    if (pageIndex == null || pageIndex < 0 || pageIndex >= count) {
      throw PdfEngineException(
        EngineErrorKind.invalidPage,
        'Page $pageIndex is outside 0..${count - 1}',
      );
    }
    return pageIndex;
  }
}

/// Lower runs first.
abstract final class _Rank {
  static const control = 0;
  static const search = 5;

  static int render(RenderPriority priority) => switch (priority) {
    RenderPriority.visiblePreview => 1,
    RenderPriority.visibleTile => 2,
    RenderPriority.nearPreview => 3,
    RenderPriority.nearTile => 4,
    RenderPriority.thumbnail => 6,
    RenderPriority.background => 7,
  };
}

final class _Job {
  _Job(
    this.id,
    this.rank,
    this.run, {
    this.documentId,
    this.render,
    this.isSearch = false,
  });

  final int id;
  final int rank;
  final void Function() run;
  final int? documentId;
  final RenderRequest? render;
  final bool isSearch;
  int sequence = 0;

  /// Same rank: newer render generation first, then oldest request first.
  bool isBefore(_Job other) {
    if (rank != other.rank) return rank < other.rank;
    final a = render?.generation, b = other.render?.generation;
    if (a != null && b != null && a != b) return a > b;
    return sequence < other.sequence;
  }

  void fail(EngineHost host, EngineErrorKind kind, String message) =>
      host.reply(ErrorReply(id, kind, message));

  /// Answers a job dropped because its document closed or the engine
  /// stopped. An interrupted search ends with an error, so it never looks
  /// complete.
  void dropForClose(EngineHost host, {bool shutdown = false}) {
    if (render != null) {
      host.reply(SkippedReply(id, SkipReason.closed));
    } else if (shutdown) {
      host.reply(ErrorReply(id, EngineErrorKind.stopped, 'Engine stopped'));
    } else {
      host.reply(
        ErrorReply(id, EngineErrorKind.unknownDocument, 'Document closed'),
      );
    }
  }
}
