// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../reader/reader_page.dart';
import '../settings/app_settings.dart';

/// The app's own folder in shared storage on Android, where
/// `adb push file.pdf <dir>` works without any permission.
const androidDevDocumentsDir =
    '/storage/emulated/0/Android/data/io.github.frerol.doxapdf/files';

/// Temporary developer list of the PDFs in [directory], so the reader can
/// be tried on a device before file opening exists (issue #49).
class DevDocuments extends StatefulWidget {
  const DevDocuments({
    super.key,
    required this.engine,
    required this.directory,
    this.settings,
  });

  /// App settings the reader opens with.
  final SettingsController? settings;

  /// Starts or returns the app's engine.
  final Future<PdfEngine> Function() engine;
  final String directory;

  @override
  State<DevDocuments> createState() => _DevDocumentsState();
}

class _DevDocumentsState extends State<DevDocuments> {
  List<File> _files = const [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _scan() {
    var files = <File>[];
    try {
      final dir = Directory(widget.directory);
      if (dir.existsSync()) {
        files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.pdf'))
            .toList();
        files.sort((a, b) => a.path.compareTo(b.path));
      }
    } on FileSystemException {
      // An unreadable folder shows as empty.
    }
    setState(() => _files = files);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.devDocumentsTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: _scan,
                  icon: const Icon(Icons.refresh),
                  tooltip: l10n.devDocumentsRefresh,
                ),
              ],
            ),
            if (_files.isEmpty)
              Text(l10n.devDocumentsEmpty(widget.directory))
            else
              for (final file in _files)
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(file.uri.pathSegments.last),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReaderPage(
                        engine: widget.engine(),
                        source: FileSource(file.path),
                        title: file.uri.pathSegments.last,
                        settings: widget.settings,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
