// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:doxa_platform/doxa_platform.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'features/settings/app_settings.dart';
import 'src/doxa_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The app draws edge to edge on every Android version; full screen
  // (FR-VIEW-012) returns to this mode when it ends.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  final platform = DoxaPlatform();
  final settings = SettingsController(
    Platform.isAndroid
        ? FileSettingsStore(platform.getDataDirectory())
        : MemorySettingsStore(),
  );
  await settings.load();
  runApp(
    DoxaApp(
      settings: settings,
      accentColor: Platform.isAndroid
          ? () async {
              final argb = await platform.getAccentColor();
              return argb == null ? null : Color(argb);
            }
          : null,
    ),
  );
}
