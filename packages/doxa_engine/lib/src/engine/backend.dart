// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_core/doxa_core.dart';

import '../api/types.dart';
import 'protocol.dart';

/// Synchronous document operations, called only from the engine isolate.
///
/// `PdfiumBackend` implements it on PDFium; tests use fakes to check the
/// scheduling in `EngineHost` without native code. Failures are thrown as
/// [PdfEngineException].
abstract interface class EngineBackend {
  /// Opens a document as [documentId] (a [DocumentOpened] handle id).
  OpenResult open(int documentId, DocumentSource source, String? password);

  bool isOpen(int documentId);
  int pageCount(int documentId);
  void close(int documentId);

  PageDetails pageDetails(int documentId, int pageIndex);
  List<OutlineNode> outline(int documentId);
  List<PageLink> pageLinks(int documentId, int pageIndex);
  PageText pageText(int documentId, int pageIndex);

  /// The annotations of one page, read from the editing instance.
  List<Annotation> annotations(int documentId, int pageIndex);

  /// Applies [edit] to the editing instance. Returns the changed
  /// annotation for an update, null otherwise.
  Annotation? edit(int documentId, AnnotationEdit edit);

  /// Saves the editing instance to [path] (ADR-0008). When [path] is the
  /// file the document was opened from, the render instance reopens on
  /// the saved file.
  SaveResult save(int documentId, String path);

  /// The number of digital signatures in the document.
  int signatureCount(int documentId);
  RenderedPixels render(RenderRequest request);

  /// Closes every document and releases the library.
  void dispose();
}
