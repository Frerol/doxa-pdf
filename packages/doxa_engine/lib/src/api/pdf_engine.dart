// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_core/doxa_core.dart';

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

  /// The annotations of one page (FR-ANNO-002), read from the editing
  /// instance (ADR-0005), in the page's `/Annots` order. Popups, links
  /// and form widgets are left out: popups belong to their markup, and
  /// links ([pageLinks]) and form fields are not study annotations.
  Future<List<Annotation>> annotations(DocumentHandle document, int pageIndex);

  /// Adds Doxa's text markup and ink to their pages, in the editing
  /// instance (ADR-0008). Each needs an id from `DoxaMarker.newId`. The
  /// file changes only when it is saved.
  Future<void> addAnnotations(
    DocumentHandle document,
    List<Annotation> annotations,
  );

  /// Changes the annotation with [annotation]'s id, on its page, to match
  /// it, and returns it as the page now holds it. Doxa's own annotations
  /// are rebuilt. Another app's are patched key by key: only colour,
  /// opacity, note, author and flags change, and a markup loses its
  /// appearance when its colour changes (readers draw it without one).
  /// Other changes fail with [EngineErrorKind.unsupportedEdit]. A foreign
  /// annotation without `/NM` gets one, so its id changes.
  Future<Annotation> updateAnnotation(
    DocumentHandle document,
    Annotation annotation,
  );

  /// Deletes the annotations with [ids] from page [pageIndex], with their
  /// popups. Nothing is deleted when an id is not on the page
  /// ([EngineErrorKind.unknownAnnotation]).
  Future<void> deleteAnnotations(
    DocumentHandle document,
    int pageIndex,
    List<String> ids,
  );

  /// Searches every page in order and streams the hits page by page.
  /// Cancelling the subscription stops the search.
  Stream<SearchHit> search(DocumentHandle document, SearchQuery query);

  /// Closes every document and stops the engine.
  Future<void> dispose();
}
