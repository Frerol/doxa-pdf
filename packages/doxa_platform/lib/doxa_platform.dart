// SPDX-License-Identifier: GPL-3.0-or-later

import 'doxa_platform_platform_interface.dart';

class DoxaPlatform {
  Future<String?> getPlatformVersion() {
    return DoxaPlatformPlatform.instance.getPlatformVersion();
  }
}
