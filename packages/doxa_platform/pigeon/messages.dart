// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:pigeon/pigeon.dart';

// This file is where you define the interface between Dart code and host
// platform code. After editing this file, run
//   dart run pigeon --input pigeon/messages.dart
// to re-generate all of the output files.
//
// If you add new platforms to your plugin, add the corresponding output
// options in the PigeonOptions below.
//
// To learn more about Pigeon, see https://pub.dev/packages/pigeon.

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'doxa_platform',
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut: 'android/src/main/kotlin/io/github/frerol/doxapdf/doxa_platform/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'io.github.frerol.doxapdf.doxa_platform',
    ),
  ),
)
@HostApi()
abstract class DoxaPlatformPluginApi {
  /// Returns the system version of the host platform.
  String getPlatformVersion();
}
