// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:isolate';

import 'package:doxa_core/doxa_core.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

import '../api/pdf_engine.dart';
import '../api/types.dart';
import 'engine_host.dart';
import 'pdfium_backend.dart';
import 'protocol.dart';

/// [PdfEngine] on PDFium. Every PDFium call runs in one long-lived engine
/// isolate (ADR-0005), so the UI isolate never blocks on native code.
///
/// PDFium is process-wide state, so only one engine may run at a time:
/// [spawn] throws while another one has not been disposed.
final class PdfiumEngine implements PdfEngine {
  PdfiumEngine._(this._commands, this._port, Stream<Object?> messages) {
    messages.listen(_onMessage);
  }

  static var _running = false;

  /// Starts the engine isolate. [libraryPath] overrides where PDFium is
  /// loaded from (see `openPdfium`).
  ///
  /// Throws [PdfEngineException] with [EngineErrorKind.stopped] when PDFium
  /// cannot be loaded or the isolate dies while starting, and [StateError]
  /// when another engine is running.
  static Future<PdfiumEngine> spawn({String? libraryPath}) async {
    if (_running) {
      throw StateError('A PdfiumEngine is already running; dispose it first');
    }
    _running = true;
    // One port receives replies, uncaught errors and the exit notice (null).
    final port = ReceivePort('doxa-engine');
    try {
      await Isolate.spawn(
        _engineMain,
        (port.sendPort, libraryPath),
        debugName: 'doxa-pdfium-engine',
        onExit: port.sendPort,
        onError: port.sendPort,
      );
      final messages = port.asBroadcastStream();
      final first = await messages.first;
      switch (first) {
        case EngineReady(:final commands):
          return PdfiumEngine._(commands, port, messages);
        case EngineStartFailed(:final message):
          throw PdfEngineException(EngineErrorKind.stopped, message);
        default:
          throw PdfEngineException(
            EngineErrorKind.stopped,
            'The engine isolate stopped while starting: $first',
          );
      }
    } catch (_) {
      port.close();
      _running = false;
      rethrow;
    }
  }

  final SendPort _commands;
  final ReceivePort _port;

  final _pending = <int, Completer<Object?>>{};
  final _searches = <int, StreamController<SearchHit>>{};
  var _nextId = 1;
  String? _stoppedReason;

  @override
  Future<OpenResult> open(DocumentSource source, {String? password}) async {
    final id = _nextId++;
    return await _request(id, OpenCommand(id, source, password)) as OpenResult;
  }

  @override
  Future<void> close(DocumentHandle document) {
    final id = _nextId++;
    return _request(id, CloseCommand(id, document.id));
  }

  @override
  Future<PageDetails> pageDetails(DocumentHandle document, int pageIndex) =>
      _query<PageDetails>(QueryKind.pageDetails, document, pageIndex);

  @override
  Future<List<OutlineNode>> outline(DocumentHandle document) =>
      _query<List<OutlineNode>>(QueryKind.outline, document);

  @override
  Future<List<PageLink>> pageLinks(DocumentHandle document, int pageIndex) =>
      _query<List<PageLink>>(QueryKind.pageLinks, document, pageIndex);

  @override
  Future<PageText> pageText(DocumentHandle document, int pageIndex) =>
      _query<PageText>(QueryKind.pageText, document, pageIndex);

  @override
  Future<List<Annotation>> annotations(
    DocumentHandle document,
    int pageIndex,
  ) => _query<List<Annotation>>(QueryKind.annotations, document, pageIndex);

  @override
  Future<void> addAnnotations(
    DocumentHandle document,
    List<Annotation> annotations,
  ) => _edit(document, AddAnnotationsEdit(annotations));

  @override
  Future<Annotation> updateAnnotation(
    DocumentHandle document,
    Annotation annotation,
  ) async => (await _edit(document, UpdateAnnotationEdit(annotation)))!;

  @override
  Future<void> deleteAnnotations(
    DocumentHandle document,
    int pageIndex,
    List<String> ids,
  ) => _edit(document, DeleteAnnotationsEdit(pageIndex, ids));

  @override
  Future<SaveResult> save(DocumentHandle document, String path) async {
    final id = _nextId++;
    return await _request(id, SaveCommand(id, document.id, path)) as SaveResult;
  }

  @override
  Future<int> signatureCount(DocumentHandle document) =>
      _query<int>(QueryKind.signatureCount, document);

  Future<Annotation?> _edit(
    DocumentHandle document,
    AnnotationEdit edit,
  ) async {
    final id = _nextId++;
    return await _request(id, EditCommand(id, document.id, edit))
        as Annotation?;
  }

  Future<T> _query<T>(QueryKind kind, DocumentHandle doc, [int? page]) async {
    final id = _nextId++;
    return await _request(id, QueryCommand(id, kind, doc.id, page)) as T;
  }

  @override
  Future<RenderResult> render(
    RenderRequest request, {
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      return const RenderSkipped(SkipReason.cancelled);
    }
    final id = _nextId++;
    final reply = _request(id, RenderCommand(id, request));
    final removeListener = cancel?.onCancel(() {
      if (_pending.containsKey(id)) _send(CancelCommand(id));
    });
    try {
      return switch (await reply) {
        final RenderedPixels pixels => pixels.materialize(),
        final RenderSkipped skipped => skipped,
        final other => throw StateError('Unexpected render reply: $other'),
      };
    } finally {
      removeListener?.call();
    }
  }

  @override
  void setGeneration(DocumentHandle document, int generation) =>
      _send(GenerationCommand(document.id, generation));

  @override
  Stream<SearchHit> search(DocumentHandle document, SearchQuery query) {
    final id = _nextId++;
    late final StreamController<SearchHit> controller;
    controller = StreamController<SearchHit>(
      onListen: () {
        final reason = _stoppedReason;
        if (reason != null) {
          controller
            ..addError(PdfEngineException(EngineErrorKind.stopped, reason))
            ..close();
          return;
        }
        _searches[id] = controller;
        _send(SearchCommand(id, document.id, query));
      },
      onCancel: () {
        if (_searches.remove(id) != null) _send(CancelCommand(id));
      },
    );
    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    if (_stoppedReason != null) return;
    final id = _nextId++;
    try {
      await _request(id, ShutdownCommand(id));
    } on PdfEngineException catch (e) {
      // The exit notice can overtake the shutdown reply.
      if (e.kind != EngineErrorKind.stopped) rethrow;
    } finally {
      _onStopped('The engine was disposed');
    }
  }

  Future<Object?> _request(int id, EngineCommand command) {
    final reason = _stoppedReason;
    if (reason != null) {
      return Future.error(PdfEngineException(EngineErrorKind.stopped, reason));
    }
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send(command);
    return completer.future;
  }

  void _send(EngineCommand command) {
    if (_stoppedReason == null) _commands.send(command);
  }

  void _onMessage(Object? message) {
    switch (message) {
      case EngineReply():
        _onReply(message);
      case null:
        _onStopped('The engine isolate exited');
      case [final error, final stack]:
        // An uncaught error; the isolate exits next.
        _onStopped('The engine isolate failed: $error\n$stack');
    }
  }

  void _onReply(EngineReply message) {
    final search = _searches[message.id];
    if (search != null) {
      switch (message) {
        case SearchHitsReply(:final hits):
          hits.forEach(search.add);
        case SearchDoneReply():
          _searches.remove(message.id);
          search.close();
        case ErrorReply(:final kind, message: final text):
          _searches.remove(message.id);
          search
            ..addError(PdfEngineException(kind, text))
            ..close();
        case ValueReply() || RenderReply() || SkippedReply():
          break;
      }
      return;
    }
    final completer = _pending.remove(message.id);
    if (completer == null) return;
    switch (message) {
      case ValueReply(:final value):
        completer.complete(value);
      case RenderReply(:final pixels):
        completer.complete(pixels);
      case SkippedReply(:final reason):
        completer.complete(RenderSkipped(reason));
      case ErrorReply(:final kind, message: final text):
        completer.completeError(PdfEngineException(kind, text));
      case SearchHitsReply() || SearchDoneReply():
        completer.completeError(StateError('Unexpected search reply'));
    }
  }

  void _onStopped(String reason) {
    if (_stoppedReason != null) return;
    _stoppedReason = reason;
    final error = PdfEngineException(EngineErrorKind.stopped, reason);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
    for (final search in _searches.values) {
      search
        ..addError(error)
        ..close();
    }
    _searches.clear();
    _port.close();
    _running = false;
  }
}

/// Entry point of the engine isolate.
void _engineMain((SendPort, String?) args) {
  final (replies, libraryPath) = args;
  final PdfiumBackend backend;
  try {
    backend = PdfiumBackend(openPdfium(path: libraryPath));
  } catch (e) {
    replies.send(EngineStartFailed('$e'));
    return;
  }
  final commands = ReceivePort('doxa-engine-commands');
  final host = EngineHost(backend, replies.send);
  commands.listen((message) {
    if (message is! EngineCommand) return;
    host.handle(message);
    if (message is ShutdownCommand) commands.close();
  });
  replies.send(EngineReady(commands.sendPort));
}
