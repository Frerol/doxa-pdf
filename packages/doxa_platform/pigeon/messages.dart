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

/// A document source leased from Android. Release it after closing PDFium.
class PlatformPdf {
  PlatformPdf(
    this.leaseId,
    this.uri,
    this.displayName,
    this.path,
    this.persistedRead,
    this.persistedWrite,
  );

  int leaseId;
  String uri;
  String displayName;
  String path;
  bool persistedRead;
  bool persistedWrite;
}

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

  /// Opens a web or mail link in another app (FR-VIEW-010). Returns false
  /// when no app can open it. Callers confirm with the user first.
  bool openUri(String uri);

  /// The system accent colour (ARGB) for dynamic colour on Android 12+
  /// (FR-SET-001), or null where there is none.
  int? getAccentColor();

  /// Keeps the screen on while reading (FR-VIEW-013).
  void setKeepScreenOn(bool keepOn);

  /// The app's private data directory, for settings and the database.
  String getDataDirectory();

  @asyncCallback
  PlatformPdf? pickPdf();

  @asyncCallback
  PlatformPdf openPersistedPdf(String uri);

  @asyncCallback
  PlatformPdf? takeIncomingPdf();

  void releasePdf(int leaseId);
}

@FlutterApi()
abstract class PdfIntentApi {
  @asyncCallback
  void incomingPdfAvailable();
}
