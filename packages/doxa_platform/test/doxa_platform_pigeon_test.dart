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
}

/// Fake implementation of the Pigeon API that provides a pre-set response.
class FakeDoxaPlatformPluginApi implements DoxaPlatformPluginApi {
  FakeDoxaPlatformPluginApi({required this.platformVersion});

  final String platformVersion;

  @override
  Future<String> getPlatformVersion() async {
    return platformVersion;
  }

  @override
  // ignore: non_constant_identifier_names
  BinaryMessenger? get pigeonVar_binaryMessenger => null;

  @override
  // ignore: non_constant_identifier_names
  String get pigeonVar_messageChannelSuffix => '';
}
