// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../reader/color_mode.dart';
import '../reader/reader_geometry.dart';

/// App-wide settings (FR-SET-001, FR-SET-002, FR-VIEW-005, FR-VIEW-006,
/// FR-VIEW-013).
final class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.dynamicColor = true,
    this.languageCode,
    this.colorMode = PageColorMode.normal,
    this.customBackground = defaultCustomBackground,
    this.customText = defaultCustomText,
    this.keepScreenOn = false,
    this.readerMode = ReaderMode.continuous,
    this.coverPage = true,
    this.tapZones = true,
    this.keepZoomOnTurn = false,
  });

  final ThemeMode themeMode;

  /// Use the system accent colour on Android 12+ (Material You).
  final bool dynamicColor;

  /// `en` or `pt`, or null to follow the system language.
  final String? languageCode;

  /// The page colour mode documents open with.
  final PageColorMode colorMode;
  final Color customBackground;
  final Color customText;

  /// Keep the screen on while a document is open.
  final bool keepScreenOn;

  /// Layout defaults every document opens with (FR-VIEW-006); right to
  /// left is per document (FR-VIEW-019) and not kept here.
  final ReaderMode readerMode;
  final bool coverPage;
  final bool tapZones;
  final bool keepZoomOnTurn;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? dynamicColor,
    String? Function()? languageCode,
    PageColorMode? colorMode,
    Color? customBackground,
    Color? customText,
    bool? keepScreenOn,
    ReaderMode? readerMode,
    bool? coverPage,
    bool? tapZones,
    bool? keepZoomOnTurn,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    dynamicColor: dynamicColor ?? this.dynamicColor,
    languageCode: languageCode == null ? this.languageCode : languageCode(),
    colorMode: colorMode ?? this.colorMode,
    customBackground: customBackground ?? this.customBackground,
    customText: customText ?? this.customText,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    readerMode: readerMode ?? this.readerMode,
    coverPage: coverPage ?? this.coverPage,
    tapZones: tapZones ?? this.tapZones,
    keepZoomOnTurn: keepZoomOnTurn ?? this.keepZoomOnTurn,
  );

  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'dynamicColor': dynamicColor,
    'languageCode': languageCode,
    'colorMode': colorMode.name,
    'customBackground': customBackground.toARGB32(),
    'customText': customText.toARGB32(),
    'keepScreenOn': keepScreenOn,
    'readerMode': readerMode.name,
    'coverPage': coverPage,
    'tapZones': tapZones,
    'keepZoomOnTurn': keepZoomOnTurn,
  };

  /// Reads settings written by [toJson]; unknown or broken values fall back
  /// to the defaults, so an old or damaged file never stops the app.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    const defaults = AppSettings();
    T pick<T>(String key, T fallback) {
      final value = json[key];
      return value is T ? value : fallback;
    }

    E named<E extends Enum>(List<E> values, String key, E fallback) {
      final name = json[key];
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    final language = json['languageCode'];
    return AppSettings(
      themeMode: named(ThemeMode.values, 'themeMode', defaults.themeMode),
      dynamicColor: pick('dynamicColor', defaults.dynamicColor),
      languageCode: language == 'en' || language == 'pt'
          ? language as String
          : null,
      colorMode: named(PageColorMode.values, 'colorMode', defaults.colorMode),
      customBackground: Color(
        pick('customBackground', defaults.customBackground.toARGB32()),
      ),
      customText: Color(pick('customText', defaults.customText.toARGB32())),
      keepScreenOn: pick('keepScreenOn', defaults.keepScreenOn),
      readerMode: named(ReaderMode.values, 'readerMode', defaults.readerMode),
      coverPage: pick('coverPage', defaults.coverPage),
      tapZones: pick('tapZones', defaults.tapZones),
      keepZoomOnTurn: pick('keepZoomOnTurn', defaults.keepZoomOnTurn),
    );
  }
}

/// Where settings are kept; injectable for tests.
abstract interface class SettingsStore {
  Future<Map<String, Object?>?> read();
  Future<void> write(Map<String, Object?> json);
}

/// Settings in a JSON file, written atomically (temp file, then rename).
final class FileSettingsStore implements SettingsStore {
  FileSettingsStore(this.directory);

  /// Resolves to the app's private data directory.
  final Future<String> directory;

  Future<File> get _file async => File('${await directory}/settings.json');

  @override
  Future<Map<String, Object?>?> read() async {
    try {
      final text = await (await _file).readAsString();
      final json = jsonDecode(text);
      return json is Map<String, Object?> ? json : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(Map<String, Object?> json) async {
    final file = await _file;
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(file.path);
  }
}

/// Settings that live only in memory (tests, platforms without storage).
final class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([this.json]);
  Map<String, Object?>? json;

  @override
  Future<Map<String, Object?>?> read() async => json;

  @override
  Future<void> write(Map<String, Object?> json) async => this.json = json;
}

/// Holds the current settings and saves every change.
final class SettingsController extends ValueNotifier<AppSettings> {
  SettingsController(this._store) : super(const AppSettings());

  final SettingsStore _store;
  Future<void> _saving = Future.value();

  Future<void> load() async {
    final json = await _store.read();
    if (json != null) value = AppSettings.fromJson(json);
  }

  void update(AppSettings settings) {
    if (identical(settings, value)) return;
    value = settings;
    // Saves run one after another, so the file always ends with the last.
    _saving = _saving
        .then((_) => _store.write(settings.toJson()))
        .catchError(
          (Object error) => debugPrint('Doxa: cannot save settings: $error'),
        );
  }

  /// Completes when every change so far is saved; for tests.
  Future<void> flush() => _saving;
}
