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
  Future<String?> getPlatformVersion() => Future.value('42');

  final opened = <String>[];

  @override
  Future<bool> openUri(String uri) async {
    opened.add(uri);
    return true;
  }
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
}
