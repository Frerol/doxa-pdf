// SPDX-License-Identifier: GPL-3.0-or-later

import 'dictionary_imports.dart';
import 'document_files.dart';
import 'doxa_platform_platform_interface.dart';
import 'library_folders.dart';
import 'pdf_documents.dart';

export 'dictionary_imports.dart';
export 'document_files.dart';
export 'library_folders.dart';
export 'pdf_documents.dart';

class DoxaPlatform {
  PdfDocuments get pdfDocuments => DoxaPlatformPlatform.instance.pdfDocuments;

  LibraryFolders get libraryFolders =>
      DoxaPlatformPlatform.instance.libraryFolders;

  DocumentFiles get documentFiles =>
      DoxaPlatformPlatform.instance.documentFiles;

  DictionaryImports get dictionaryImports =>
      DoxaPlatformPlatform.instance.dictionaryImports;

  Future<String?> getPlatformVersion() {
    return DoxaPlatformPlatform.instance.getPlatformVersion();
  }

  /// Schemes [openUri] accepts. Others (`file:`, `intent:`, `javascript:`,
  /// app-specific schemes) are refused, so a PDF cannot reach local files
  /// or other apps' internals through a link.
  static const openableSchemes = {'http', 'https', 'mailto'};

  /// Opens a web or mail link from a document in another app
  /// (FR-VIEW-010). Returns false when the link is refused or no app can
  /// open it. Ask the user to confirm before calling this.
  Future<bool> openUri(String uri) async {
    final parsed = Uri.tryParse(uri.trim());
    if (parsed == null ||
        !openableSchemes.contains(parsed.scheme.toLowerCase())) {
      return false;
    }
    return DoxaPlatformPlatform.instance.openUri(parsed.toString());
  }

  /// The system accent colour (ARGB) for dynamic colour (FR-SET-001), or
  /// null before Android 12 and where the platform has none.
  Future<int?> getAccentColor() async {
    try {
      return await DoxaPlatformPlatform.instance.getAccentColor();
    } on Object {
      return null;
    }
  }

  /// Keeps the screen on while [keepOn] (FR-VIEW-013). Does nothing where
  /// the platform cannot.
  Future<void> setKeepScreenOn(bool keepOn) async {
    try {
      await DoxaPlatformPlatform.instance.setKeepScreenOn(keepOn);
    } on Object {
      // Not supported here.
    }
  }

  /// The app's private data directory.
  Future<String> getDataDirectory() =>
      DoxaPlatformPlatform.instance.getDataDirectory();
}
