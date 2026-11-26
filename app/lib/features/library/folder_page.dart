// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:doxa_platform/doxa_platform.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';

/// How a library folder is sorted (FR-FILE-006). Subfolders always come
/// first.
enum FolderSort { name, modified, size }

/// Folds case and the accents of Latin letters, for name filters.
String foldName(String text) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final out = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    final index = from.indexOf(char);
    out.write(index < 0 ? char : to[index]);
  }
  return out.toString();
}

/// Sorts [entries] for display: folders first, then by [sort]. Names
/// compare without case or accents; newest and largest come first.
List<PlatformFolderEntry> sortEntries(
  Iterable<PlatformFolderEntry> entries,
  FolderSort sort,
) {
  int byName(PlatformFolderEntry a, PlatformFolderEntry b) {
    final folded = foldName(a.name).compareTo(foldName(b.name));
    return folded != 0 ? folded : a.name.compareTo(b.name);
  }

  int byField(PlatformFolderEntry a, PlatformFolderEntry b) => switch (sort) {
    FolderSort.name => 0,
    // Unknown values sort last.
    FolderSort.modified => (b.lastModified ?? -1).compareTo(
      a.lastModified ?? -1,
    ),
    FolderSort.size => (b.size ?? -1).compareTo(a.size ?? -1),
  };

  return entries.toList()..sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    final field = byField(a, b);
    return field != 0 ? field : byName(a, b);
  });
}

/// Listings already shown in this session, so going back to a folder is
/// instant; each visit still refreshes it.
final class FolderListingCache {
  final _entries = <String, List<PlatformFolderEntry>>{};

  List<PlatformFolderEntry>? get(String treeUri, String? documentId) =>
      _entries['$treeUri\n$documentId'];

  void put(
    String treeUri,
    String? documentId,
    List<PlatformFolderEntry> entries,
  ) => _entries['$treeUri\n$documentId'] = entries;
}

/// Browses one level of a library folder (FR-FILE-006): subfolders and
/// PDFs, sorted by name, date or size, with a name filter.
class FolderPage extends StatefulWidget {
  const FolderPage({
    super.key,
    required this.folders,
    required this.treeUri,
    required this.title,
    required this.onOpen,
    required this.cache,
    this.documentId,
  });

  final LibraryFolders folders;
  final String treeUri;
  final String? documentId;
  final String title;
  final FolderListingCache cache;

  /// Opens a PDF of the folder.
  final void Function(PlatformFolderEntry pdf) onOpen;

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  /// The order chosen last, kept while the app runs.
  static FolderSort _lastSort = FolderSort.name;

  FolderSort _sort = _lastSort;
  List<PlatformFolderEntry>? _entries;
  PdfAccessError? _error;
  bool _searching = false;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _entries = widget.cache.get(widget.treeUri, widget.documentId);
    unawaited(_load());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entries = await widget.folders.listFolder(
        widget.treeUri,
        documentId: widget.documentId,
      );
      widget.cache.put(widget.treeUri, widget.documentId, entries);
      if (mounted) {
        setState(() {
          _entries = entries;
          _error = null;
        });
      }
    } on PdfAccessException catch (error) {
      if (mounted) setState(() => _error = error.error);
    } on Object catch (error) {
      debugPrint('Doxa: cannot list folder: $error');
      if (mounted) setState(() => _error = PdfAccessError.unreadable);
    }
  }

  void _openFolder(PlatformFolderEntry folder) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FolderPage(
          folders: widget.folders,
          treeUri: widget.treeUri,
          documentId: folder.documentId,
          title: folder.name,
          onOpen: widget.onOpen,
          cache: widget.cache,
        ),
      ),
    );
  }

  void _setSort(FolderSort sort) {
    _lastSort = sort;
    setState(() => _sort = sort);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _query,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.librarySearch,
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: _searching ? l10n.libraryCloseSearch : l10n.librarySearch,
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query.clear();
            }),
          ),
          PopupMenuButton<FolderSort>(
            icon: const Icon(Icons.sort),
            tooltip: l10n.sortBy,
            initialValue: _sort,
            onSelected: _setSort,
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: FolderSort.name,
                checked: _sort == FolderSort.name,
                child: Text(l10n.sortName),
              ),
              CheckedPopupMenuItem(
                value: FolderSort.modified,
                checked: _sort == FolderSort.modified,
                child: Text(l10n.sortModified),
              ),
              CheckedPopupMenuItem(
                value: FolderSort.size,
                checked: _sort == FolderSort.size,
                child: Text(l10n.sortSize),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body(l10n)),
    );
  }

  Widget _body(AppLocalizations l10n) {
    final entries = _entries;
    if (entries == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null && entries == null) {
      return _Message(switch (error) {
        PdfAccessError.permissionLost => l10n.folderPermissionLost,
        PdfAccessError.missing => l10n.folderMissing,
        _ => l10n.folderUnreadable,
      });
    }
    final query = foldName(_query.text.trim());
    final shown = sortEntries(
      query.isEmpty
          ? entries!
          : entries!.where((e) => foldName(e.name).contains(query)),
      _sort,
    );
    if (shown.isEmpty) {
      return _Message(
        query.isEmpty
            ? l10n.folderEmpty
            : l10n.librarySearchEmpty(_query.text.trim()),
      );
    }
    final locale = l10n.localeName;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final entry = shown[i];
        if (entry.isDirectory) {
          return ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(entry.name),
            onTap: () => _openFolder(entry),
          );
        }
        final details = [
          if (entry.size case final size?) formatFileSize(size, locale),
          if (entry.lastModified case final modified?)
            DateFormat.yMMMd(locale)
                .format(DateTime.fromMillisecondsSinceEpoch(modified)),
        ].join(' · ');
        return ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: details.isEmpty ? null : Text(details),
          onTap: () => widget.onOpen(entry),
        );
      },
    );
  }
}

/// A file size in the units file managers show (1 KB = 1000 bytes).
String formatFileSize(int bytes, String locale) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  final number = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: digits,
  ).format(value);
  return '$number ${units[unit]}';
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ListView(
    // Scrollable, so pull to refresh works on errors too.
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(32),
    children: [
      const SizedBox(height: 48),
      Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ],
  );
}
