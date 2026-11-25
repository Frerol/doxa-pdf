// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_platform/doxa_platform_pigeon.dart';
import 'package:doxa_platform/src/messages.g.dart';
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

  @override
  // ignore: non_constant_identifier_names
  BinaryMessenger? get pigeonVar_binaryMessenger => null;

  @override
  // ignore: non_constant_identifier_names
  String get pigeonVar_messageChannelSuffix => '';
}
