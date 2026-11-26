// SPDX-License-Identifier: GPL-3.0-or-later

import 'pdf_documents.dart';
import 'src/messages.g.dart';

export 'src/messages.g.dart' show PlatformFolder, PlatformFolderEntry;

/// Folders the user grants to the library (FR-FILE-006).
abstract interface class LibraryFolders {
  /// Asks for a folder with the system picker; null when cancelled.
  Future<PlatformFolder?> pickFolder();

  /// The PDFs and subfolders directly inside [documentId] of [treeUri], or
  /// inside its root. Throws [PdfAccessException] with
  /// [PdfAccessError.permissionLost] or [PdfAccessError.missing].
  Future<List<PlatformFolderEntry>> listFolder(
    String treeUri, {
    String? documentId,
  });

  /// Gives up the grant of a folder the user removed from the library.
  Future<void> releaseFolder(String treeUri);
}
