// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_platform/doxa_platform.dart';
import 'package:doxa_platform/doxa_platform_pigeon.dart';
import 'package:doxa_platform/src/messages.g.dart'
    hide
        PlatformPdf,
        PlatformFolder,
        PlatformFolderEntry,
        PlatformMovedDocument;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a lost folder grant is reported as permissionLost (FR-FILE-006)', () {
    final api = FakeDoxaPlatformPluginApi(platformVersion: '42');
    final folders = PigeonDoxaPlatform(api: api).libraryFolders;
    expect(
      folders.listFolder('content://p/tree/1'),
      throwsA(
        isA<PdfAccessException>().having(
          (e) => e.error,
          'error',
          PdfAccessError.permissionLost,
        ),
      ),
    );
  });

  test('provider failures of file actions keep their cause (FR-FILE-011)', () {
    final api = FakeDoxaPlatformPluginApi(platformVersion: '42');
    final files = PigeonDoxaPlatform(api: api).documentFiles;
    Matcher fails(DocumentFileError error) => throwsA(
      isA<DocumentFileException>().having((e) => e.error, 'error', error),
    );
    api.fileError = 'unsupported';
    expect(
      files.move('content://p/doc/1', targetTreeUri: 'content://p/tree/t'),
      fails(DocumentFileError.unsupported),
    );
    api.fileError = 'permissionLost';
    expect(
      files.delete('content://p/doc/1'),
      fails(DocumentFileError.permissionLost),
    );
    // Codes the Dart side does not know are still failures, not crashes.
    api.fileError = 'somethingNew';
    expect(
      files.rename('content://p/doc/1', 'b.pdf'),
      fails(DocumentFileError.failed),
    );
  });

  test('staging failures keep their cause (FR-TEXT-009)', () async {
    final api = FakeDoxaPlatformPluginApi(platformVersion: '42');
    final imports = PigeonDoxaPlatform(api: api).dictionaryImports;
    api.staged = '/cache/staged';
    expect(await imports.pickFiles(), '/cache/staged');
    expect(await imports.stageArchive('/cache/pack.zip'), '/cache/staged');
    api.stageError = 'missing';
    await expectLater(
      imports.stageArchive('/cache/pack.zip'),
      throwsA(
        isA<DictionaryImportException>().having(
          (e) => e.error,
          'error',
          DictionaryImportError.missing,
        ),
      ),
    );
    for (final (code, error) in [
      ('tooLarge', DictionaryImportError.tooLarge),
      ('notDictionary', DictionaryImportError.notDictionary),
      ('somethingNew', DictionaryImportError.unreadable),
    ]) {
      api.stageError = code;
      await expectLater(
        imports.takeIncoming(),
        throwsA(
          isA<DictionaryImportException>().having(
            (e) => e.error,
            'error',
            error,
          ),
        ),
      );
    }
  });

  test('only documents inside a folder tree can be moved', () {
    const tree =
        'content://com.android.externalstorage.documents/tree/primary%3ABooks';
    expect(isInFolderTree('$tree/document/primary%3ABooks%2Fa.pdf'), isTrue);
    expect(
      isInFolderTree(
        'content://com.android.providers.downloads.documents/document/msf%3A12',
      ),
      isFalse,
    );
    expect(isInFolderTree(tree), isFalse);
    expect(isInFolderTree('file:///tree/x/document/y'), isFalse);
  });

  test('getPlatformVersion', () async {
    final api = FakeDoxaPlatformPluginApi(platformVersion: '42');
    final plugin = PigeonDoxaPlatform(api: api);

    expect(await plugin.getPlatformVersion(), '42');
  });

  test('openUri reaches the host API', () async {
    final api = FakeDoxaPlatformPluginApi(platformVersion: '42');
    final plugin = PigeonDoxaPlatform(api: api);

    expect(await plugin.openUri('https://example.org/'), isTrue);
    expect(api.opened, ['https://example.org/']);
  });

  test('picks, reopens, takes and releases leased PDFs', () async {
    final api = FakeDoxaPlatformPluginApi(platformVersion: '42');
    final documents = PigeonDoxaPlatform(api: api).pdfDocuments;

    expect(await documents.pickPdf(), isNull);
    api.pdf = PlatformPdf(
      leaseId: 7,
      uri: 'content://provider/book',
      displayName: 'Book.pdf',
      path: '/proc/self/fd/10',
      persistedRead: true,
      persistedWrite: false,
    );
    final picked = (await documents.pickPdf())!;
    expect(picked.displayName, 'Book.pdf');
    expect(picked.persistedRead, isTrue);
    expect(picked.persistedWrite, isFalse);
    expect(await documents.openPersistedPdf(picked.uri), same(picked));
    expect(api.reopened, picked.uri);
    expect(await documents.takeIncomingPdf(), same(picked));
    expect(await documents.takeIncomingPdf(), isNull);
    await documents.releasePdf(picked.leaseId);
    expect(api.released, 7);
    await expectLater(
      documents.openPersistedPdf(picked.uri),
      throwsA(
        isA<PdfAccessException>().having(
          (error) => error.error,
          'error',
          PdfAccessError.permissionLost,
        ),
      ),
    );
  });

  test('delivers the native incoming-document signal to listeners', () async {
    final documents = PigeonDoxaPlatform().pdfDocuments;
    final received = expectLater(documents.incomingPdfs, emits(null));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await messenger.handlePlatformMessage(
      'dev.flutter.pigeon.doxa_platform.PdfIntentApi.incomingPdfAvailable',
      null,
      (_) {},
    );
    await received;
  });
}

/// Fake implementation of the Pigeon API that provides a pre-set response.
class FakeDoxaPlatformPluginApi implements DoxaPlatformPluginApi {
  FakeDoxaPlatformPluginApi({required this.platformVersion});

  final String platformVersion;

  @override
  Future<String> getPlatformVersion() async {
    return platformVersion;
  }

  final opened = <String>[];

  @override
  Future<bool> openUri(String uri) async {
    opened.add(uri);
    return true;
  }

  bool? keepScreenOn;

  @override
  Future<int?> getAccentColor() async => 0xFF336699;

  @override
  Future<void> setKeepScreenOn(bool keepOn) async => keepScreenOn = keepOn;

  @override
  Future<String> getDataDirectory() async => '/data/doxa';

  PlatformPdf? pdf;
  String? reopened;
  int? released;

  @override
  Future<PlatformPdf?> pickPdf() async => pdf;

  @override
  Future<PlatformPdf> openPersistedPdf(String uri) async {
    reopened = uri;
    return pdf ?? (throw PlatformException(code: 'permissionLost'));
  }

  @override
  Future<PlatformPdf?> takeIncomingPdf() async {
    final pending = pdf;
    pdf = null;
    return pending;
  }

  @override
  Future<void> releasePdf(int leaseId) async => released = leaseId;

  List<PlatformFolderEntry>? entries;
  String? releasedFolder;

  @override
  Future<PlatformFolder?> pickFolder() async => null;

  @override
  Future<List<PlatformFolderEntry>> listFolder(
    String treeUri,
    String? documentId,
  ) async => entries ?? (throw PlatformException(code: 'permissionLost'));

  @override
  Future<void> releaseFolder(String treeUri) async => releasedFolder = treeUri;

  String fileError = 'failed';

  @override
  Future<PlatformMovedDocument> renameDocument(
    String uri,
    String displayName,
  ) => throw PlatformException(code: fileError);

  @override
  Future<PlatformMovedDocument> moveDocument(
    String uri,
    String targetTreeUri,
    String? targetDocumentId,
  ) => throw PlatformException(code: fileError);

  @override
  Future<void> deleteDocument(String uri) =>
      throw PlatformException(code: fileError);

  String? staged;
  String? stageError;

  Future<String?> _stage() async =>
      stageError == null ? staged : throw PlatformException(code: stageError!);

  @override
  Future<String?> pickDictionaryFiles() => _stage();

  @override
  Future<String?> pickDictionaryFolder() => _stage();

  @override
  Future<String?> takeIncomingDictionary() => _stage();

  @override
  Future<String> stageDictionaryArchive(String path) async => (await _stage())!;

  @override
  Future<String> getCacheDirectory() async => '/cache';

  @override
  Future<int?> getCacheFreeBytes() async => null;

  @override
  Future<bool> isNetworkMetered() async => false;

  @override
  // ignore: non_constant_identifier_names
  BinaryMessenger? get pigeonVar_binaryMessenger => null;

  @override
  // ignore: non_constant_identifier_names
  String get pigeonVar_messageChannelSuffix => '';
}
