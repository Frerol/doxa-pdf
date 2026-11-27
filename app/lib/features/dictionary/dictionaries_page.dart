// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../library/folder_page.dart' show formatFileSize;
import 'dictionary_import.dart';
import 'dictionary_library.dart';
import 'dictionary_popup.dart';

/// Settings → Dictionaries (FR-TEXT-009): each dictionary with its name,
/// size and source; enable or disable it, drag it to change the order in
/// which lookups show it, or remove it.
class DictionariesPage extends StatelessWidget {
  const DictionariesPage({
    super.key,
    required this.library,
    required this.openUri,
    this.importer,
  });

  final DictionaryLibrary library;
  final Future<bool> Function(String uri) openUri;
  final DictionaryImporter? importer;

  Future<void> _remove(BuildContext context, InstalledDictionary d) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dictionaryRemoveTitle(d.name)),
        content: Text(l10n.dictionaryRemoveMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.dictionaryRemove),
          ),
        ],
      ),
    );
    if (confirmed == true) await library.remove(d.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final importer = this.importer;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dictionariesTitle),
        actions: [
          if (importer != null) ...[
            IconButton(
              icon: const Icon(LucideIcons.fileInput),
              tooltip: l10n.dictionaryImport,
              onPressed: () => unawaited(importer.pickFiles(context)),
            ),
            IconButton(
              icon: const Icon(LucideIcons.folderInput),
              tooltip: l10n.dictionaryImportFolder,
              onPressed: () => unawaited(importer.pickFolder(context)),
            ),
          ],
        ],
      ),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final all = library.all;
          if (!library.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final importActions = importer == null
              ? null
              : _ImportButtons(importer: importer);
          if (all.isEmpty) {
            return Center(
              child: DictionaryEmptyState(
                openUri: openUri,
                importActions: importActions,
              ),
            );
          }
          final locale = l10n.localeName;
          return ReorderableListView.builder(
            header: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GetDictionariesButton(openUri: openUri, importer: importer),
                  if (importActions != null) ...[
                    const SizedBox(height: 8),
                    importActions,
                  ],
                ],
              ),
            ),
            itemCount: all.length,
            onReorderItem: (from, to) => unawaited(library.move(from, to)),
            itemBuilder: (context, i) {
              final d = all[i];
              final details = [
                formatFileSize(d.sizeBytes, locale),
                if (d.description.isNotEmpty) d.description,
              ].join(' · ');
              return ListTile(
                key: ValueKey(d.id),
                title: Text(d.name),
                subtitle: Text(
                  details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                leading: Switch(
                  value: d.enabled,
                  onChanged: (on) => unawaited(library.setEnabled(d.id, on)),
                ),
                trailing: IconButton(
                  icon: const Icon(LucideIcons.trash2),
                  tooltip: l10n.dictionaryRemoveTooltip(d.name),
                  onPressed: () => _remove(context, d),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ImportButtons extends StatelessWidget {
  const _ImportButtons({required this.importer});

  final DictionaryImporter importer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
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
    );
  }
}
