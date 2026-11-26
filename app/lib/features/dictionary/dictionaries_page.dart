// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../library/folder_page.dart' show formatFileSize;
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
    this.onImport,
  });

  final DictionaryLibrary library;
  final Future<bool> Function(String uri) openUri;
  final VoidCallback? onImport;

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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dictionariesTitle)),
      floatingActionButton: onImport == null || library.all.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: onImport,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(l10n.dictionaryImport),
            ),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final all = library.all;
          if (!library.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (all.isEmpty) {
            return Center(
              child: DictionaryEmptyState(openUri: openUri, onImport: onImport),
            );
          }
          final locale = l10n.localeName;
          return ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
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
                  icon: const Icon(Icons.delete_outline),
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
