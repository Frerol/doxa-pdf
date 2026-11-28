// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dictionary_imports.dart';
import 'document_files.dart';
import 'download_conditions.dart';
import 'doxa_platform_platform_interface.dart';
import 'library_folders.dart';
import 'pdf_documents.dart';
import 'pdf_saves.dart';
import 'src/messages.g.dart';

/// An implementation of [DoxaPlatformPlatform] that uses Pigeon, for
/// non-web platforms.
class PigeonDoxaPlatform extends DoxaPlatformPlatform {
  /// Creates a new plugin implementation instance.
  PigeonDoxaPlatform({@visibleForTesting DoxaPlatformPluginApi? api})
    : _hostApi = api ?? DoxaPlatformPluginApi();

  final DoxaPlatformPluginApi _hostApi;

  @override
  late final PdfDocuments pdfDocuments = _PigeonPdfDocuments(_hostApi);

  @override
  late final PdfSaves pdfSaves = _PigeonPdfSaves(_hostApi);

  @override
  late final LibraryFolders libraryFolders = _PigeonLibraryFolders(_hostApi);

  @override
  late final DocumentFiles documentFiles = _PigeonDocumentFiles(_hostApi);

  @override
  late final DictionaryImports dictionaryImports = _PigeonDictionaryImports(
    _hostApi,
  );

  @override
  late final DownloadConditions downloadConditions = _PigeonDownloadConditions(
    _hostApi,
  );

  @override
  Future<String?> getPlatformVersion() async {
    return _hostApi.getPlatformVersion();
  }

  @override
  Future<bool> openUri(String uri) => _hostApi.openUri(uri);

  @override
  Future<int?> getAccentColor() => _hostApi.getAccentColor();

  @override
  Future<void> setKeepScreenOn(bool keepOn) => _hostApi.setKeepScreenOn(keepOn);

  @override
  Future<String> getDataDirectory() => _hostApi.getDataDirectory();
}

class _PigeonPdfDocuments implements PdfDocuments, PdfIntentApi {
  _PigeonPdfDocuments(this._hostApi);

  final DoxaPlatformPluginApi _hostApi;
  late final _incoming = StreamController<void>.broadcast(
    onListen: () => PdfIntentApi.setUp(this),
    onCancel: () => PdfIntentApi.setUp(null),
  );

  @override
  Stream<void> get incomingPdfs => _incoming.stream;

  @override
  Future<void> incomingPdfAvailable() async => _incoming.add(null);

  @override
  Future<PlatformPdf?> pickPdf() => _access(_hostApi.pickPdf);

  @override
  Future<PlatformPdf> openPersistedPdf(String uri) =>
      _access(() => _hostApi.openPersistedPdf(uri));

  @override
  Future<PlatformPdf?> takeIncomingPdf() => _access(_hostApi.takeIncomingPdf);

  @override
  Future<void> releasePdf(int leaseId) => _hostApi.releasePdf(leaseId);

  Future<T> _access<T>(Future<T> Function() action) => _pdfAccess(action);
}

class _PigeonPdfSaves implements PdfSaves {
  _PigeonPdfSaves(this._hostApi);

  final DoxaPlatformPluginApi _hostApi;

  @override
  Future<bool> canWrite(String uri) =>
      _saveAction(() => _hostApi.canWrite(uri));

  @override
  Future<void> writeBack(String uri, String tempPath) =>
      _saveAction(() => _hostApi.writeBack(uri, tempPath));

  @override
  Future<String?> saveCopy(String tempPath, String displayName) =>
      _saveAction(() => _hostApi.savePdfCopy(tempPath, displayName));

  @override
  Future<void> share(String uri) => _saveAction(() => _hostApi.sharePdf(uri));

  Future<T> _saveAction<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (error) {
      throw PdfSaveException(
        switch (error.code) {
          'permissionLost' => PdfSaveError.permissionLost,
          'readOnly' => PdfSaveError.readOnly,
          'noSpace' => PdfSaveError.noSpace,
          'mismatch' => PdfSaveError.mismatch,
          _ => PdfSaveError.failed,
        },
        recoveryPath: switch (error.details) {
          {'recoveryPath': final String path} => path,
          _ => null,
        },
      );
    }
  }
}

class _PigeonLibraryFolders implements LibraryFolders {
  _PigeonLibraryFolders(this._hostApi);

  final DoxaPlatformPluginApi _hostApi;

  @override
  Future<PlatformFolder?> pickFolder() => _pdfAccess(_hostApi.pickFolder);

  @override
  Future<List<PlatformFolderEntry>> listFolder(
    String treeUri, {
    String? documentId,
  }) => _pdfAccess(() => _hostApi.listFolder(treeUri, documentId));

  @override
  Future<void> releaseFolder(String treeUri) => _hostApi.releaseFolder(treeUri);
}

class _PigeonDocumentFiles implements DocumentFiles {
  _PigeonDocumentFiles(this._hostApi);

  final DoxaPlatformPluginApi _hostApi;

  @override
  Future<PlatformMovedDocument> rename(String uri, String displayName) =>
      _fileAction(() => _hostApi.renameDocument(uri, displayName));

  @override
  Future<PlatformMovedDocument> move(
    String uri, {
    required String targetTreeUri,
    String? targetDocumentId,
  }) => _fileAction(
    () => _hostApi.moveDocument(uri, targetTreeUri, targetDocumentId),
  );

  @override
  Future<void> delete(String uri) =>
      _fileAction(() => _hostApi.deleteDocument(uri));
}

class _PigeonDictionaryImports
    implements DictionaryImports, DictionaryIntentApi {
  _PigeonDictionaryImports(this._hostApi);

  final DoxaPlatformPluginApi _hostApi;
  late final _incoming = StreamController<void>.broadcast(
    onListen: () => DictionaryIntentApi.setUp(this),
    onCancel: () => DictionaryIntentApi.setUp(null),
  );

  @override
  Stream<void> get incoming => _incoming.stream;

  @override
  Future<void> incomingDictionaryAvailable() async => _incoming.add(null);

  @override
  Future<String?> pickFiles() => _staging(_hostApi.pickDictionaryFiles);

  @override
  Future<String?> pickFolder() => _staging(_hostApi.pickDictionaryFolder);

  @override
  Future<String?> takeIncoming() => _staging(_hostApi.takeIncomingDictionary);

  @override
  Future<String> stageArchive(String path) async =>
      (await _staging(() => _hostApi.stageDictionaryArchive(path)))!;

  /// Maps host errors to [DictionaryImportException].
  static Future<String?> _staging(Future<String?> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (error) {
      throw DictionaryImportException(switch (error.code) {
        'missing' => DictionaryImportError.missing,
        'permissionLost' => DictionaryImportError.permissionLost,
        'notDictionary' => DictionaryImportError.notDictionary,
        'tooLarge' => DictionaryImportError.tooLarge,
        _ => DictionaryImportError.unreadable,
      });
    }
  }
}

class _PigeonDownloadConditions implements DownloadConditions {
  _PigeonDownloadConditions(this._hostApi);

  final DoxaPlatformPluginApi _hostApi;

  @override
  Future<String> cacheDirectory() => _hostApi.getCacheDirectory();

  @override
  Future<int?> freeBytes() => _hostApi.getCacheFreeBytes();

  @override
  Future<bool> isMetered() => _hostApi.isNetworkMetered();
}

/// Maps host errors to [DocumentFileException].
Future<T> _fileAction<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on PlatformException catch (error) {
    throw DocumentFileException(switch (error.code) {
      'missing' => DocumentFileError.missing,
      'permissionLost' => DocumentFileError.permissionLost,
      'unsupported' => DocumentFileError.unsupported,
      _ => DocumentFileError.failed,
    });
  }
}

/// Maps host errors to [PdfAccessException].
Future<T> _pdfAccess<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on PlatformException catch (error) {
    throw PdfAccessException(switch (error.code) {
      'missing' => PdfAccessError.missing,
      'notPdf' => PdfAccessError.notPdf,
      'permissionLost' => PdfAccessError.permissionLost,
      'unreadable' => PdfAccessError.unreadable,
      _ => throw error,
    });
  }
}
