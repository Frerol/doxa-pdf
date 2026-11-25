// SPDX-License-Identifier: GPL-3.0-or-later

import 'types.dart';

/// The PDF engine used by the app (docs/plan/04-pdf-engine.md §5).
///
/// The PDFium implementation, `PdfiumEngine`, runs every PDFium call in one
/// worker isolate. `FakePdfEngine` (in `package:doxa_engine/testing.dart`)
/// serves UI tests without native code.
///
/// Calls with a bad handle or page index throw [PdfEngineException].
/// Problems with the file itself are reported as values ([OpenResult]).
abstract interface class PdfEngine {
  /// Opens a document. Encrypted documents need [password] (FR-FILE-003).
  Future<OpenResult> open(DocumentSource source, {String? password});

  /// Closes a document. Pending renders for it complete as
  /// [RenderSkipped] with [SkipReason.closed]. Closing twice is a no-op.
  Future<void> close(DocumentHandle document);

  /// Crop box and rotation of one page.
  Future<PageDetails> pageDetails(DocumentHandle document, int pageIndex);

  /// The document outline; empty when it has none.
  Future<List<OutlineNode>> outline(DocumentHandle document);

  /// The link annotations of one page.
  Future<List<PageLink>> pageLinks(DocumentHandle document, int pageIndex);

  /// Renders part of a page (ADR-0005), with foreign annotations.
  Future<RenderResult> render(RenderRequest request, {CancelToken? cancel});

  /// Starts a new viewport generation for [document]. Queued renders of
  /// older generations are dropped unless their priority is
  /// [RenderPriority.keptWhenStale].
  void setGeneration(DocumentHandle document, int generation);

  /// The text layer of one page.
  Future<PageText> pageText(DocumentHandle document, int pageIndex);

  /// Searches every page in order and streams the hits page by page.
  /// Cancelling the subscription stops the search.
  Stream<SearchHit> search(DocumentHandle document, SearchQuery query);

  /// Closes every document and stops the engine.
  Future<void> dispose();
}
