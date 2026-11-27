// SPDX-License-Identifier: GPL-3.0-or-later

/// Why staging a dictionary failed (FR-TEXT-009).
enum DictionaryImportError {
  /// The file is gone.
  missing,

  /// The app may no longer read the file.
  permissionLost,

  /// A `.zip` that is not a valid zip archive.
  notDictionary,

  /// More than 2 GiB or 4096 files, so possibly a zip bomb.
  tooLarge,

  /// Any other failure to read or copy.
  unreadable,
}

class DictionaryImportException implements Exception {
  const DictionaryImportException(this.error);

  final DictionaryImportError error;

  @override
  String toString() => 'DictionaryImportException(${error.name})';
}

/// Gets dictionaries from the system (FR-TEXT-009, FR-TEXT-012). Each method
/// copies what it gets into a new staging folder in the app's cache, with
/// every `.zip` extracted, and returns the folder's path. The caller
/// validates the folder's StarDict sets, keeps them and deletes the folder.
/// Failures throw [DictionaryImportException].
abstract interface class DictionaryImports {
  /// Picks a `.zip` or loose StarDict files; null when cancelled.
  Future<String?> pickFiles();

  /// Picks a folder; null when cancelled.
  Future<String?> pickFolder();

  /// Signals that a `.zip` opened with "Open with" is waiting.
  Stream<void> get incoming;

  /// Stages the next `.zip` opened with "Open with", or returns null when
  /// none is waiting, including one from a cold start.
  Future<String?> takeIncoming();

  /// Stages the `.zip` at [path], one the app downloaded into its cache
  /// (ADR-0010). The `.zip` is left in place for the caller to delete.
  Future<String> stageArchive(String path);
}
