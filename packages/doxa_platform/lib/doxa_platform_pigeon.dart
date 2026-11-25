// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'doxa_platform_platform_interface.dart';
import 'src/messages.g.dart';

/// An implementation of [DoxaPlatformPlatform] that uses Pigeon, for
/// non-web platforms.
class PigeonDoxaPlatform extends DoxaPlatformPlatform {
  /// Creates a new plugin implementation instance.
  PigeonDoxaPlatform({@visibleForTesting DoxaPlatformPluginApi? api})
    : _hostApi = api ?? DoxaPlatformPluginApi();

  final DoxaPlatformPluginApi _hostApi;

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
