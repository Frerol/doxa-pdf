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
}
