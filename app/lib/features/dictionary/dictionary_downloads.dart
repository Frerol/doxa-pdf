// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:doxa_platform/doxa_platform.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../library/folder_page.dart' show formatFileSize;
import 'dictionary_catalog.dart';
import 'dictionary_import.dart';
import 'dictionary_library.dart';

/// Whether a catalogue pack is installed (ADR-0010).
enum PackStatus { available, installed, updateAvailable }

/// How a tap on a pack ended.
sealed class PackOutcome {
  const PackOutcome();
}

final class PackInstalled extends PackOutcome {
  const PackInstalled(this.report);

  final InstallReport report;
}

final class PackNoSpace extends PackOutcome {
  const PackNoSpace(this.neededBytes);

  final int neededBytes;
}

final class PackFailed extends PackOutcome {
  const PackFailed(this.error);

  final DownloadError error;
}

final class PackImportFailed extends PackOutcome {
  const PackImportFailed(this.error);

  final DictionaryImportError error;
}

/// The packs Doxa builds, downloaded in the app when the user asks
/// (ADR-0010, UX §9). One download runs at a time; it keeps running when
/// the list is closed and shows its progress when it opens again.
final class DictionaryDownloads extends ChangeNotifier {
  DictionaryDownloads({
    required this.library,
    required this.imports,
    required this.conditions,
    DictionaryDownloader? downloader,
    Uri? catalog,
  }) : downloader = downloader ?? DictionaryDownloader(),
       catalog = catalog ?? catalogUri;

  final DictionaryLibrary library;
  final DictionaryImports imports;
  final DownloadConditions conditions;
  final DictionaryDownloader downloader;
  final Uri catalog;

  List<CatalogPack>? _packs;
  DownloadError? _catalogError;
  bool _loading = false;
  Map<String, String> _installedIfo = const {};
  String? _active;
  int _received = 0;
  bool _installing = false;
  DownloadCancel? _cancel;
  bool _cleaned = false;

  /// The catalogue's packs, or null before it loads or when it failed.
  List<CatalogPack>? get packs => _packs;
  DownloadError? get catalogError => _catalogError;
  bool get loading => _loading;

  /// The id of the pack being downloaded or installed.
  String? get active => _active;
  int get received => _received;
  bool get installing => _installing;

  /// Fetches the catalogue. Called when the list opens, never otherwise.
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _catalogError = null;
    notifyListeners();
    try {
      if (!_cleaned) {
        _cleaned = true;
        await DictionaryDownloader.cleanUp(
          Directory(await conditions.cacheDirectory()),
        );
      }
      _packs = await downloader.fetchCatalog(catalog);
      await _hashInstalled();
    } on DownloadException catch (error) {
      _packs = null;
      _catalogError = error.error;
    } on Object catch (error) {
      debugPrint('Doxa: cannot load the dictionary catalogue: $error');
      _packs = null;
      _catalogError = DownloadError.failed;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _hashInstalled() async {
    final hashes = <String, String>{};
    for (final d in library.all) {
      try {
        hashes[d.id] = await fileSha256(File(d.ifoPath));
      } on FileSystemException {
        // A dictionary removed meanwhile is simply not matched.
      }
    }
    _installedIfo = hashes;
  }

  /// The installed dictionary that [pack] is, if any: the same bookname.
  InstalledDictionary? installedAs(CatalogPack pack) {
    for (final d in library.all) {
      if (d.name == pack.bookName) return d;
    }
    return null;
  }

  PackStatus statusOf(CatalogPack pack) {
    final installed = installedAs(pack);
    if (installed == null) return PackStatus.available;
    final hash = _installedIfo[installed.id];
    // An unknown hash is not reported as an update.
    return hash == null || hash == pack.ifoSha256
        ? PackStatus.installed
        : PackStatus.updateAvailable;
  }

  /// Whether a large download should ask first.
  Future<bool> isMetered() async {
    try {
      return await conditions.isMetered();
    } on Object {
      return true;
    }
  }

  /// Cancels the running download.
  void cancel() => _cancel?.cancel();

  /// Downloads [pack], checks it and installs it, enabled. An update
  /// replaces the installed pack in its place in the list.
  Future<PackOutcome> install(CatalogPack pack) async {
    if (_active != null) return const PackFailed(DownloadError.cancelled);
    final replacing = statusOf(pack) == PackStatus.updateAvailable
        ? installedAs(pack)
        : null;
    _active = pack.id;
    _received = 0;
    _installing = false;
    final cancel = _cancel = DownloadCancel();
    notifyListeners();
    File? file;
    try {
      final cache = Directory(await conditions.cacheDirectory());
      // The download and its extracted copy are in the cache together.
      final needed = pack.sizeBytes + pack.unpackedBytes;
      final free = await conditions.freeBytes();
      if (free != null && free < needed) return PackNoSpace(needed);
      file = await downloader.download(
        pack,
        cache,
        cancel: cancel,
        onProgress: (received) {
          _received = received;
          notifyListeners();
        },
      );
      _installing = true;
      notifyListeners();
      final staging = await imports.stageArchive(file.path);
      await file.delete();
      file = null;
      final report = await library.install(staging);
      if (replacing != null && report.added.isNotEmpty) {
        await _replace(replacing, pack);
      }
      await _hashInstalled();
      return PackInstalled(report);
    } on DownloadException catch (error) {
      return PackFailed(error.error);
    } on DictionaryImportException catch (error) {
      return PackImportFailed(error.error);
    } on Object catch (error) {
      debugPrint('Doxa: cannot install a dictionary pack: $error');
      return const PackImportFailed(DictionaryImportError.unreadable);
    } finally {
      if (file != null) {
        try {
          await file.delete();
        } on FileSystemException {
          // Cleaned up at the next start.
        }
      }
      _active = null;
      _cancel = null;
      _installing = false;
      notifyListeners();
    }
  }

  /// Puts the new build of [pack] where [old] was, then removes [old].
  Future<void> _replace(InstalledDictionary old, CatalogPack pack) async {
    final all = library.all;
    final from = all.lastIndexWhere(
      (d) => d.name == pack.bookName && d.id != old.id,
    );
    final to = all.indexWhere((d) => d.id == old.id);
    if (from < 0 || to < 0) return;
    await library.move(from, to);
    await library.remove(old.id);
  }
}

/// Get dictionaries (ADR-0010, UX §9): the packs Doxa builds, with their
/// language, size, source and licence, each downloaded with one tap.
/// Without a network it says so and still offers the import actions.
class DictionaryDownloadsPage extends StatefulWidget {
  const DictionaryDownloadsPage({
    super.key,
    required this.downloads,
    this.importer,
  });

  final DictionaryDownloads downloads;
  final DictionaryImporter? importer;

  @override
  State<DictionaryDownloadsPage> createState() =>
      _DictionaryDownloadsPageState();
}

class _DictionaryDownloadsPageState extends State<DictionaryDownloadsPage> {
  DictionaryDownloads get _downloads => widget.downloads;

  @override
  void initState() {
    super.initState();
    unawaited(_downloads.refresh());
  }

  Future<void> _get(CatalogPack pack) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final locale = l10n.localeName;
    if (await _downloads.isMetered()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.dictionaryMeteredTitle),
          content: Text(
            l10n.dictionaryMeteredMessage(
              pack.name,
              formatFileSize(pack.sizeBytes, locale),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.dictionaryDownload),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    final outcome = await _downloads.install(pack);
    final message = switch (outcome) {
      PackInstalled(:final report) => importMessage(l10n, report),
      PackNoSpace(:final neededBytes) => l10n.dictionaryNoSpace(
        formatFileSize(neededBytes, locale),
      ),
      PackFailed(error: DownloadError.cancelled) => null,
      PackFailed(error: DownloadError.offline) => l10n.dictionaryOffline,
      PackFailed(error: DownloadError.corrupt) => l10n.dictionaryCorrupt,
      PackFailed(error: DownloadError.failed) => l10n.dictionaryDownloadFailed,
      PackImportFailed(error: DictionaryImportError.tooLarge) =>
        l10n.dictionaryTooLarge,
      PackImportFailed(error: DictionaryImportError.notDictionary) =>
        l10n.dictionaryCorrupt,
      PackImportFailed() => l10n.fileUnreadable,
    };
    if (message != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dictionaryGet)),
      body: ListenableBuilder(
        listenable: Listenable.merge([_downloads, _downloads.library]),
        builder: (context, _) {
          final packs = _downloads.packs;
          if (packs == null) {
            if (_downloads.loading || _downloads.catalogError == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _Unavailable(
              offline: _downloads.catalogError == DownloadError.offline,
              onRetry: () => unawaited(_downloads.refresh()),
              importer: widget.importer,
            );
          }
          return ListView(
            children: [
              for (final pack in packs)
                _PackTile(
                  pack: pack,
                  downloads: _downloads,
                  onGet: () => unawaited(_get(pack)),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.dictionaryDownloadsNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.pack,
    required this.downloads,
    required this.onGet,
  });

  final CatalogPack pack;
  final DictionaryDownloads downloads;
  final VoidCallback onGet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final details = [
      formatFileSize(pack.sizeBytes, l10n.localeName),
      if (pack.source.isNotEmpty) pack.source,
      if (pack.licence.isNotEmpty) pack.licence,
    ].join(' · ');
    final active = downloads.active == pack.id;
    final busy = downloads.active != null;
    final status = downloads.statusOf(pack);
    final Widget trailing;
    if (active) {
      trailing = downloads.installing
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          : IconButton(
              icon: const Icon(LucideIcons.x),
              tooltip: l10n.dictionaryCancelDownload(pack.name),
              onPressed: downloads.cancel,
            );
    } else {
      trailing = switch (status) {
        PackStatus.installed => Tooltip(
          message: l10n.dictionaryInstalled,
          child: Icon(
            LucideIcons.circleCheck,
            semanticLabel: l10n.dictionaryInstalled,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        PackStatus.updateAvailable => TextButton(
          onPressed: busy ? null : onGet,
          child: Text(l10n.dictionaryUpdate),
        ),
        PackStatus.available => IconButton(
          icon: const Icon(LucideIcons.download),
          tooltip: l10n.dictionaryDownloadTooltip(pack.name),
          onPressed: busy ? null : onGet,
        ),
      };
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(pack.name),
          subtitle: Text(
            [
              details,
              if (pack.description.isNotEmpty) pack.description,
            ].join('\n'),
          ),
          isThreeLine: pack.description.isNotEmpty,
          trailing: trailing,
          onTap: !busy && status == PackStatus.available ? onGet : null,
        ),
        if (active)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              value: downloads.installing
                  ? null
                  : downloads.received / pack.sizeBytes,
              semanticsLabel: l10n.dictionaryDownloading(pack.name),
            ),
          ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.offline,
    required this.onRetry,
    this.importer,
  });

  final bool offline;
  final VoidCallback onRetry;
  final DictionaryImporter? importer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final importer = this.importer;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline ? LucideIcons.cloudOff : LucideIcons.circleAlert,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              offline ? l10n.dictionaryOffline : l10n.dictionaryCatalogFailed,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(LucideIcons.refreshCw),
              label: Text(l10n.retry),
              onPressed: onRetry,
            ),
            if (importer != null) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(LucideIcons.fileInput),
                    label: Text(l10n.dictionaryImport),
                    onPressed: () => unawaited(importer.pickFiles(context)),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(LucideIcons.folderInput),
                    label: Text(l10n.dictionaryImportFolder),
                    onPressed: () => unawaited(importer.pickFolder(context)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
