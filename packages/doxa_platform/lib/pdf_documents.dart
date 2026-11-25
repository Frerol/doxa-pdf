// SPDX-License-Identifier: GPL-3.0-or-later

import 'src/messages.g.dart';

export 'src/messages.g.dart' show PlatformPdf;

enum PdfAccessError { missing, unreadable, notPdf, permissionLost }

class PdfAccessException implements Exception {
  const PdfAccessException(this.error);

  final PdfAccessError error;
}

/// Access to PDFs supplied by the operating system.
abstract interface class PdfDocuments {
  /// Null when the picker is cancelled.
  Future<PlatformPdf?> pickPdf();

  /// Reopens the URI from a [PlatformPdf] with persisted read access.
  /// Throws [PdfAccessException] if the grant was lost or the file is gone.
  Future<PlatformPdf> openPersistedPdf(String uri);

  /// Signals that the incoming queue may have new documents.
  Stream<void> get incomingPdfs;

  /// Takes the next queued request, including requests from a cold start.
  /// A failed request is consumed and throws [PdfAccessException].
  Future<PlatformPdf?> takeIncomingPdf();

  /// Releases the descriptor or cache file after the reader and engine close.
  Future<void> releasePdf(int leaseId);
}
