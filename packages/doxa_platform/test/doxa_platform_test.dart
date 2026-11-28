// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_platform/doxa_platform.dart';
import 'package:doxa_platform/doxa_platform_pigeon.dart';
import 'package:doxa_platform/doxa_platform_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDoxaPlatformPlatform
    with MockPlatformInterfaceMixin
    implements DoxaPlatformPlatform {
  @override
  PdfDocuments get pdfDocuments => throw UnimplementedError();

  @override
  PdfSaves get pdfSaves => throw UnimplementedError();

  @override
  LibraryFolders get libraryFolders => throw UnimplementedError();

  @override
  DocumentFiles get documentFiles => throw UnimplementedError();

  @override
  DictionaryImports get dictionaryImports => throw UnimplementedError();

  @override
  DownloadConditions get downloadConditions => throw UnimplementedError();

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

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
}

void main() {
  final initialPlatform = DoxaPlatformPlatform.instance;

  test('PigeonDoxaPlatform is the default instance', () {
    expect(initialPlatform, isInstanceOf<PigeonDoxaPlatform>());
  });

  test('getPlatformVersion', () async {
    final doxaPlatformPlugin = DoxaPlatform();
    final fakePlatform = MockDoxaPlatformPlatform();
    DoxaPlatformPlatform.instance = fakePlatform;

    expect(await doxaPlatformPlugin.getPlatformVersion(), '42');
  });

  test('openUri passes web and mail links and refuses the rest', () async {
    final fakePlatform = MockDoxaPlatformPlatform();
    DoxaPlatformPlatform.instance = fakePlatform;
    final plugin = DoxaPlatform();

    expect(await plugin.openUri('https://example.org/a b'), isTrue);
    expect(await plugin.openUri(' HTTP://example.org '), isTrue);
    expect(await plugin.openUri('mailto:someone@example.org'), isTrue);
    for (final refused in [
      'file:///sdcard/secret.pdf',
      'intent://scan/#Intent;end',
      'javascript:alert(1)',
      'content://media/1',
      'not a uri at all',
      '',
    ]) {
      expect(await plugin.openUri(refused), isFalse, reason: refused);
    }
    expect(fakePlatform.opened, hasLength(3));
  });

  test('accent colour, keep screen on and data directory', () async {
    final fakePlatform = MockDoxaPlatformPlatform();
    DoxaPlatformPlatform.instance = fakePlatform;
    final plugin = DoxaPlatform();

    expect(await plugin.getAccentColor(), 0xFF336699);
    await plugin.setKeepScreenOn(true);
    expect(fakePlatform.keepScreenOn, isTrue);
    expect(await plugin.getDataDirectory(), '/data/doxa');
  });
}
