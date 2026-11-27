// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:material_ui/material_ui.dart';

import '../features/dev/dev_documents.dart';
import '../features/dictionary/dictionary_downloads.dart';
import '../features/dictionary/dictionary_import.dart';
import '../features/dictionary/dictionary_library.dart';
import '../features/library/document_identity.dart';
import '../features/library/library_home.dart';
import '../features/library/library_repository.dart';
import '../features/settings/app_settings.dart';
import '../l10n/gen/app_localizations.dart';
import 'doxa_theme.dart';

/// Seed color of the Doxa PDF Material 3 theme (docs/plan/05-ux-design.md §5).
const Color doxaSeedColor = Color(0xFF7048E8);

Future<PdfEngine>? _pdfium;

/// The app's PDFium engine, started on first use and kept for the app's
/// lifetime (one engine per process).
/// A failed start is not kept, so the next call tries again.
Future<PdfEngine> loadPdfiumEngine() =>
    _pdfium ??= PdfiumEngine.spawn().catchError((Object error) {
      _pdfium = null;
      throw error;
    });

/// Reads the system accent colour, or null where there is none.
typedef AccentColorLoader = Future<Color?> Function();

/// Root widget of Doxa PDF.
class DoxaApp extends StatefulWidget {
  const DoxaApp({
    super.key,
    this.engine = loadPdfiumEngine,
    this.devDocumentsDir,
    this.settings,
    this.accentColor,
    this.pdfDocuments,
    this.library,
    this.thumbnails,
    this.identify,
    this.libraryFolders,
    this.documentFiles,
    this.dictionaries,
    this.dictionaryLookup,
    this.dictionaryImports,
    this.downloadConditions,
    this.openUri,
    this.clock = DateTime.now,
  });

  final Future<PdfEngine> Function() engine;
  final PdfDocuments? pdfDocuments;

  /// The library database; documents are not recorded when null (tests).
  final LibraryRepository? library;
  final ThumbnailStore? thumbnails;

  /// Library folder access; the platform's on Android by default.
  final LibraryFolders? libraryFolders;

  /// Rename, move and delete (FR-FILE-011); the platform's on Android by
  /// default.
  final DocumentFiles? documentFiles;

  /// Computes document identities; `documentIdentity` by default.
  final DocumentIdentifier? identify;

  /// App settings; in memory only when null (tests).
  final SettingsController? settings;

  /// The system accent colour for dynamic colour (FR-SET-001), read again
  /// whenever the app comes back to the foreground (the wallpaper may have
  /// changed).
  final AccentColorLoader? accentColor;

  /// Installed dictionaries and their lookup (FR-TEXT-008); the reader's
  /// Dictionary action and Settings → Dictionaries are hidden without them.
  final DictionaryLibrary? dictionaries;
  final DictionaryLookup? dictionaryLookup;

  /// Gets dictionaries from the system picker and "Open with"
  /// (FR-TEXT-009); the platform's on Android by default.
  final DictionaryImports? dictionaryImports;

  /// What dictionary downloads check first (ADR-0010); the platform's on
  /// Android by default. Get dictionaries opens the browser without it.
  final DownloadConditions? downloadConditions;

  /// Opens a web page in the browser; the platform's by default.
  final Future<bool> Function(String uri)? openUri;

  /// Folder listed by the temporary developer document list; by default the
  /// app's own folder on Android, and none elsewhere.
  final String? devDocumentsDir;

  /// The time the library labels last reads against ("today").
  final DateTime Function() clock;

  @override
  State<DoxaApp> createState() => _DoxaAppState();
}

class _DoxaAppState extends State<DoxaApp> with WidgetsBindingObserver {
  SettingsController? _ownSettings;

  late final DictionaryImports? _imports =
      widget.dictionaryImports ??
      (Platform.isAndroid ? DoxaPlatform().dictionaryImports : null);

  late final DictionaryImporter? _importer = switch ((
    widget.dictionaries,
    _imports,
  )) {
    (final library?, final imports?) => DictionaryImporter(
      library: library,
      imports: imports,
    ),
    _ => null,
  };

  late final DictionaryDownloads? _downloads = switch ((
    widget.dictionaries,
    _imports,
    widget.downloadConditions ??
        (Platform.isAndroid ? DoxaPlatform().downloadConditions : null),
  )) {
    (final library?, final imports?, final conditions?) => DictionaryDownloads(
      library: library,
      imports: imports,
      conditions: conditions,
    ),
    _ => null,
  };
  Color? _accent;

  SettingsController get settings =>
      widget.settings ??
      (_ownSettings ??= SettingsController(MemorySettingsStore()));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAccent();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadAccent();
  }

  void _loadAccent() {
    final loader = widget.accentColor;
    if (loader == null) return;
    loader().then((color) {
      if (mounted && color != _accent) setState(() => _accent = color);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ownSettings?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: settings,
      builder: (context, value, _) => _app(value),
    );
  }

  Widget _app(AppSettings value) {
    final seed = value.dynamicColor
        ? (_accent ?? doxaSeedColor)
        : doxaSeedColor;
    final code = value.languageCode;
    final openUri = widget.openUri ?? DoxaPlatform().openUri;
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      themeMode: value.themeMode,
      theme: doxaTheme(seed: seed, brightness: Brightness.light),
      darkTheme: doxaTheme(seed: seed, brightness: Brightness.dark),
      locale: code == null ? null : Locale(code),
      // Flutter 3.47+ moved Material/Cupertino out of the SDK. The delegate
      // list generated by gen-l10n still points at flutter_localizations, so
      // use material_ui's own delegates instead.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final dictionaries = widget.dictionaries;
        final lookup = widget.dictionaryLookup;
        if (dictionaries == null || lookup == null || child == null) {
          return child ?? const SizedBox.shrink();
        }
        final importer = _importer;
        return DictionaryScope(
          library: dictionaries,
          lookup: lookup,
          openUri: openUri,
          importer: importer,
          downloads: _downloads,
          child: importer == null
              ? child
              : IncomingDictionaries(importer: importer, child: child),
        );
      },
      home: LibraryHome(
        openUri: openUri,
        engine: widget.engine,
        pdfDocuments:
            widget.pdfDocuments ??
            (Platform.isAndroid ? DoxaPlatform().pdfDocuments : null),
        settings: settings,
        library: widget.library,
        thumbnails: widget.thumbnails,
        libraryFolders:
            widget.libraryFolders ??
            (Platform.isAndroid ? DoxaPlatform().libraryFolders : null),
        documentFiles:
            widget.documentFiles ??
            (Platform.isAndroid ? DoxaPlatform().documentFiles : null),
        identify: widget.identify ?? documentIdentity,
        devDocumentsDir:
            widget.devDocumentsDir ??
            (Platform.isAndroid ? androidDevDocumentsDir : null),
        clock: widget.clock,
      ),
    );
  }
}
