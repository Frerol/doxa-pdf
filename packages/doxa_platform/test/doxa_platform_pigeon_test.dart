// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_platform/doxa_platform.dart';
import 'package:doxa_platform/doxa_platform_pigeon.dart';
import 'package:doxa_platform/src/messages.g.dart' hide PlatformPdf;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  @override
  // ignore: non_constant_identifier_names
  BinaryMessenger? get pigeonVar_binaryMessenger => null;

  @override
  // ignore: non_constant_identifier_names
  String get pigeonVar_messageChannelSuffix => '';
}
