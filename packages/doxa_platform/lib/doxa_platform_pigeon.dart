// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'doxa_platform_platform_interface.dart';
import 'library_folders.dart';
import 'pdf_documents.dart';
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
  late final LibraryFolders libraryFolders = _PigeonLibraryFolders(_hostApi);

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
