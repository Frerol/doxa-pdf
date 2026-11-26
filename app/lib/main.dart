// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:doxa_platform/doxa_platform.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'features/dictionary/dictionary_library.dart';
import 'features/library/library_database.dart';
import 'features/library/library_repository.dart';
import 'features/settings/app_settings.dart';
import 'src/doxa_app.dart';
import 'src/doxa_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
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
  // The library lives next to the settings in the app's private folder.
  final dataDirectory = Platform.isAndroid
      ? await platform.getDataDirectory()
      : null;
  // Dictionaries the user imported (FR-TEXT-009); found in the background.
  final dictionaries = dataDirectory == null
      ? null
      : DictionaryLibrary('$dataDirectory/dictionaries');
  unawaited(dictionaries?.load());
  runApp(
    DoxaApp(
      settings: settings,
      dictionaries: dictionaries,
      dictionaryLookup: dictionaries == null ? null : IsolateDictionaryLookup(),
      library: dataDirectory == null
          ? null
          : LibraryRepository(LibraryDatabase.inDirectory(dataDirectory)),
      thumbnails: dataDirectory == null
          ? null
          : ThumbnailStore('$dataDirectory/thumbnails'),
      accentColor: Platform.isAndroid
          ? () async {
              final argb = await platform.getAccentColor();
              return argb == null ? null : Color(argb);
            }
          : null,
    ),
  );
}
