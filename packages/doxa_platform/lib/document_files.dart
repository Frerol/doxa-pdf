// SPDX-License-Identifier: GPL-3.0-or-later

import 'src/messages.g.dart';

export 'src/messages.g.dart' show PlatformMovedDocument;

/// Why a rename, move or delete failed (FR-FILE-011).
enum DocumentFileError {
  /// The document is gone.
  missing,

  /// The app lost its grant on the document or its folder.
  permissionLost,

  /// The provider cannot do this with the document (for example, move a
  /// file that is not in a library folder, or to another storage).
  unsupported,

  /// The provider refused for another reason.
  failed,
}

class DocumentFileException implements Exception {
  const DocumentFileException(this.error);

  final DocumentFileError error;

  @override
  String toString() => 'DocumentFileException(${error.name})';
}

/// Renames, moves and deletes the user's documents (FR-FILE-011). Every
/// method throws [DocumentFileException] on failure.
abstract interface class DocumentFiles {
  /// Renames [uri] to [displayName]; the result tells where it is now.
  Future<PlatformMovedDocument> rename(String uri, String displayName);

  /// Moves [uri], a document in a library folder, into [targetDocumentId]
  /// of [targetTreeUri], or into the folder's root when it is null.
  Future<PlatformMovedDocument> move(
    String uri, {
    required String targetTreeUri,
    String? targetDocumentId,
  });

  /// Deletes [uri].
  Future<void> delete(String uri);
}

/// True when [uri] is a document inside a library folder, the only kind
/// [DocumentFiles.move] can move.
bool isInFolderTree(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.scheme != 'content') return false;
  final segments = parsed.pathSegments;
  return segments.length >= 4 &&
      segments[0] == 'tree' &&
      segments[2] == 'document';
}
