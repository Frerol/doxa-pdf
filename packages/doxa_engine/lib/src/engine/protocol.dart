// SPDX-License-Identifier: GPL-3.0-or-later

/// Messages between `PdfiumEngine` and its engine isolate. Both sides run
/// the same program, so these plain classes are sent as they are.
library;

import 'dart:isolate';

import '../api/types.dart';

/// Client → engine. [id] matches replies to requests.
sealed class EngineCommand {
  const EngineCommand(this.id);
  final int id;
}

final class OpenCommand extends EngineCommand {
  const OpenCommand(super.id, this.source, this.password);
  final DocumentSource source;
  final String? password;
}

final class CloseCommand extends EngineCommand {
  const CloseCommand(super.id, this.documentId);
  final int documentId;
}

enum QueryKind { pageDetails, outline, pageLinks, pageText }

final class QueryCommand extends EngineCommand {
  const QueryCommand(super.id, this.kind, this.documentId, [this.pageIndex]);
  final QueryKind kind;
  final int documentId;
  final int? pageIndex;
}

final class RenderCommand extends EngineCommand {
  const RenderCommand(super.id, this.request);
  final RenderRequest request;
}

final class SearchCommand extends EngineCommand {
  const SearchCommand(super.id, this.documentId, this.query);
  final int documentId;
  final SearchQuery query;
}

/// Cancels request [id] (a render or a search). No reply for searches.
final class CancelCommand extends EngineCommand {
  const CancelCommand(super.id);
}

/// Sets the viewport generation of a document. Has no reply.
final class GenerationCommand extends EngineCommand {
  const GenerationCommand(this.documentId, this.generation) : super(0);
  final int documentId;
  final int generation;
}

final class ShutdownCommand extends EngineCommand {
  const ShutdownCommand(super.id);
}

/// Engine → client.
sealed class EngineReply {
  const EngineReply(this.id);
  final int id;
}

final class ValueReply extends EngineReply {
  const ValueReply(super.id, this.value);
  final Object? value;
}

final class ErrorReply extends EngineReply {
  const ErrorReply(super.id, this.kind, this.message);
  final EngineErrorKind kind;
  final String message;
}

final class RenderReply extends EngineReply {
  const RenderReply(super.id, this.pixels);
  final RenderedPixels pixels;
}

final class SkippedReply extends EngineReply {
  const SkippedReply(super.id, this.reason);
  final SkipReason reason;
}

final class SearchHitsReply extends EngineReply {
  const SearchHitsReply(super.id, this.hits);
  final List<SearchHit> hits;
}

final class SearchDoneReply extends EngineReply {
  const SearchDoneReply(super.id);
}

/// Sent once at start-up: the port for commands, or why the engine could
/// not start (for example, PDFium is missing).
final class EngineReady {
  const EngineReady(this.commands);
  final SendPort commands;
}

final class EngineStartFailed {
  const EngineStartFailed(this.message);
  final String message;
}

/// Rendered pixels moved between isolates without a copy.
final class RenderedPixels {
  const RenderedPixels(this.width, this.height, this.data);
  final int width;
  final int height;
  final TransferableTypedData data;

  RenderedBitmap materialize() =>
      RenderedBitmap(width, height, data.materialize().asUint8List());
}
