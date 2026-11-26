// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:pigeon/pigeon.dart';

// This file is where you define the interface between Dart code and host
// platform code. After editing this file, run
//   dart run pigeon --input pigeon/messages.dart
// to re-generate all of the output files.
//
// If you add new platforms to your plugin, add the corresponding output
// options in the PigeonOptions below.
//
// To learn more about Pigeon, see https://pub.dev/packages/pigeon.

/// A document source leased from Android. Release it after closing PDFium.
class PlatformPdf {
  PlatformPdf(
    this.leaseId,
    this.uri,
    this.displayName,
    this.path,
    this.persistedRead,
    this.persistedWrite,
  );

  int leaseId;
  String uri;
  String displayName;
  String path;
  bool persistedRead;
  bool persistedWrite;
}

/// A folder tree the user granted with the system folder picker
/// (FR-FILE-006). [treeUri] keeps a persisted grant until released.
class PlatformFolder {
  PlatformFolder(this.treeUri, this.displayName);

  String treeUri;
  String displayName;
}

/// A PDF or a subfolder inside a granted folder tree.
class PlatformFolderEntry {
  PlatformFolderEntry(
    this.documentId,
    this.uri,
    this.name,
    this.isDirectory,
    this.size,
    this.lastModified,
  );

  /// Pass to [DoxaPlatformPluginApi.listFolder] to open a subfolder.
  String documentId;

  /// Document URI under the tree; opens a PDF with `openPersistedPdf`.
  String uri;
  String name;
  bool isDirectory;

  /// Bytes, or null when the provider does not say (and for folders).
  int? size;

  /// Milliseconds since the epoch, or null when unknown.
  int? lastModified;
}

/// Where a document is after a rename or a move (FR-FILE-011).
class PlatformMovedDocument {
  PlatformMovedDocument(this.uri, this.displayName, this.persisted);

  /// The document's URI now; providers may give it a new one.
  String uri;

  /// The name the provider gave it, which may differ from the one asked
  /// for (some providers add a number to avoid a clash).
  String displayName;

  /// False when the app could not keep a lasting grant on [uri], so the
  /// library cannot reopen the document from there.
  bool persisted;
}

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'doxa_platform',
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut: 'android/src/main/kotlin/io/github/frerol/doxapdf/doxa_platform/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'io.github.frerol.doxapdf.doxa_platform',
    ),
  ),
)
@HostApi()
abstract class DoxaPlatformPluginApi {
  /// Returns the system version of the host platform.
  String getPlatformVersion();

  /// Opens a web or mail link in another app (FR-VIEW-010). Returns false
  /// when no app can open it. Callers confirm with the user first.
  bool openUri(String uri);

  /// The system accent colour (ARGB) for dynamic colour on Android 12+
  /// (FR-SET-001), or null where there is none.
  int? getAccentColor();

  /// Keeps the screen on while reading (FR-VIEW-013).
  void setKeepScreenOn(bool keepOn);

  /// The app's private data directory, for settings and the database.
  String getDataDirectory();

  @asyncCallback
  PlatformPdf? pickPdf();

  @asyncCallback
  PlatformPdf openPersistedPdf(String uri);

  @asyncCallback
  PlatformPdf? takeIncomingPdf();

  void releasePdf(int leaseId);

  /// Asks the user for a folder and keeps read and write access to it
  /// (FR-FILE-006). Null when the picker is cancelled.
  @asyncCallback
  PlatformFolder? pickFolder();

  /// The PDFs and subfolders directly inside [documentId] of the tree
  /// [treeUri], or inside its root when [documentId] is null. Fails with
  /// `permissionLost` or `missing`.
  @asyncCallback
  List<PlatformFolderEntry> listFolder(String treeUri, String? documentId);

  /// Gives up the persisted grant of a folder the user removed.
  void releaseFolder(String treeUri);

  /// Renames the document [uri] to [displayName] (FR-FILE-011). Fails with
  /// `missing`, `permissionLost`, `unsupported` or `failed`.
  @asyncCallback
  PlatformMovedDocument renameDocument(String uri, String displayName);

  /// Moves the document [uri], which must lie in a library folder, into the
  /// folder [targetDocumentId] of the tree [targetTreeUri], or into its
  /// root when [targetDocumentId] is null (FR-FILE-011). Fails like
  /// [renameDocument].
  @asyncCallback
  PlatformMovedDocument moveDocument(
    String uri,
    String targetTreeUri,
    String? targetDocumentId,
  );

  /// Deletes the document [uri] (FR-FILE-011). Fails like [renameDocument].
  @asyncCallback
  void deleteDocument(String uri);

  /// Asks for dictionary files (a `.zip` or loose StarDict files) and
  /// copies them into a new staging folder in the cache, extracting each
  /// `.zip` (FR-TEXT-009). Returns the folder's path, or null when the
  /// picker is cancelled. Fails with `missing`, `permissionLost`,
  /// `notDictionary`, `tooLarge` or `unreadable`.
  @asyncCallback
  String? pickDictionaryFiles();

  /// Like [pickDictionaryFiles], for a folder picked with the system's
  /// folder picker. No lasting grant is kept.
  @asyncCallback
  String? pickDictionaryFolder();

  /// Stages the next dictionary `.zip` opened with "Open with"
  /// (FR-TEXT-012), or returns null when none is waiting.
  @asyncCallback
  String? takeIncomingDictionary();
}

@FlutterApi()
abstract class PdfIntentApi {
  @asyncCallback
  void incomingPdfAvailable();
}

@FlutterApi()
abstract class DictionaryIntentApi {
  /// A dictionary `.zip` was opened with "Open with".
  @asyncCallback
  void incomingDictionaryAvailable();
}
