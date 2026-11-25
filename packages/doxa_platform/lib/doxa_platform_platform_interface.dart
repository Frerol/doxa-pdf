// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'doxa_platform_pigeon.dart';

abstract class DoxaPlatformPlatform extends PlatformInterface {
  /// Constructs a DoxaPlatformPlatform.
  DoxaPlatformPlatform() : super(token: _token);

  static final Object _token = Object();

  static DoxaPlatformPlatform _instance = PigeonDoxaPlatform();

  /// The instance of [DoxaPlatformPlatform] to use.
  ///
  /// Defaults to [PigeonDoxaPlatform].
  static DoxaPlatformPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DoxaPlatformPlatform] when
  /// they register themselves.
  static set instance(DoxaPlatformPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Opens [uri] in another app; see [DoxaPlatform.openUri].
  Future<bool> openUri(String uri) {
    throw UnimplementedError('openUri() has not been implemented.');
  }
}
