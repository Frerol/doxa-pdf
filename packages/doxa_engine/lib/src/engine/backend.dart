// SPDX-License-Identifier: GPL-3.0-or-later

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
  RenderedPixels render(RenderRequest request);

  /// Closes every document and releases the library.
  void dispose();
}
