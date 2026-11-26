// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../dev/dev_documents.dart';
import '../reader/reader_page.dart';
import '../settings/app_settings.dart';
import '../settings/settings_page.dart';
import 'document_identity.dart';
import 'library_repository.dart';
import 'library_thumbnails.dart';

/// Computes a document identity from a readable path (injectable in tests).
typedef DocumentIdentifier = Future<String> Function(String path);

/// The home screen (issue #50): Recents and Favorites as tabs with a list
/// each (FR-FILE-004, FR-FILE-005, FR-BOOK-002), a name filter, and
/// "Open file". Opening a document records it in the library and restores
/// its reading state (FR-VIEW-006).
class LibraryHome extends StatefulWidget {
  const LibraryHome({
    super.key,
    required this.engine,
    required this.settings,
    this.library,
    this.thumbnails,
    this.pdfDocuments,
    this.devDocumentsDir,
    this.identify = documentIdentity,
    this.clock = DateTime.now,
  });

  final Future<PdfEngine> Function() engine;
  final SettingsController settings;

  /// Null where there is no database: documents open but are not recorded.
  final LibraryRepository? library;
  final ThumbnailStore? thumbnails;
  final PdfDocuments? pdfDocuments;
  final String? devDocumentsDir;
  final DocumentIdentifier identify;
  final DateTime Function() clock;

  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> {
  StreamSubscription<void>? _incoming;
  bool _draining = false;
  bool _incomingPending = false;
  bool _picking = false;
  bool _searching = false;
  final _query = TextEditingController();

  /// Bumped when a thumbnail is written, so the lists load it again.
  final _thumbnailsChanged = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _incoming = widget.pdfDocuments?.incomingPdfs.listen((_) => _onIncoming());
    WidgetsBinding.instance.addPostFrameCallback((_) => _onIncoming());
  }

  @override
  void dispose() {
    unawaited(_incoming?.cancel());
    _query.dispose();
    _thumbnailsChanged.dispose();
    super.dispose();
  }

  void _onIncoming() {
    _incomingPending = true;
    if (!_draining && mounted) unawaited(_drainIncoming());
  }

  Future<void> _drainIncoming() async {
    final documents = widget.pdfDocuments;
    if (documents == null) return;
    _draining = true;
    try {
      while (mounted && _incomingPending) {
        _incomingPending = false;
        while (mounted) {
          try {
            final pdf = await documents.takeIncomingPdf();
            if (pdf == null) break;
            await _openPlatformPdf(documents, pdf);
          } on PdfAccessException catch (error) {
            _showAccessError(error.error);
          }
        }
      }
    } on Object catch (error) {
      debugPrint('Doxa: cannot receive PDFs: $error');
      _showAccessError(PdfAccessError.unreadable);
    } finally {
      _draining = false;
    }
  }

  Future<void> _pick() async {
    final documents = widget.pdfDocuments!;
    setState(() => _picking = true);
    try {
      final pdf = await documents.pickPdf();
      if (pdf != null) await _openPlatformPdf(documents, pdf);
    } on PdfAccessException catch (error) {
      _showAccessError(error.error);
    } on Object catch (error) {
      debugPrint('Doxa: PDF picker failed: $error');
      _showAccessError(PdfAccessError.unreadable);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Opens a document from the library (FR-FILE-004, FR-FILE-005).
  Future<void> _reopen(LibraryDocument document) async {
    final uri = document.uri;
    final parsed = uri == null ? null : Uri.tryParse(uri);
    if (parsed == null) {
      _showCannotReopen(document);
      return;
    }
    if (parsed.scheme == 'file') {
      await _openFile(File(parsed.toFilePath()));
      return;
    }
    final documents = widget.pdfDocuments;
    if (documents == null) {
      _showCannotReopen(document);
      return;
    }
    try {
      final pdf = await documents.openPersistedPdf(uri!);
      await _openPlatformPdf(documents, pdf);
    } on PdfAccessException catch (error) {
      if (error.error
          case PdfAccessError.missing || PdfAccessError.permissionLost) {
        await widget.library?.forgetLocation(document.id);
        _showCannotReopen(document);
      } else {
        _showAccessError(error.error);
      }
    } on Object catch (error) {
      debugPrint('Doxa: cannot reopen ${document.displayName}: $error');
      _showAccessError(PdfAccessError.unreadable);
    }
  }

  Future<void> _openPlatformPdf(PdfDocuments documents, PlatformPdf pdf) {
    return _openRecorded(
      path: pdf.path,
      displayName: pdf.displayName,
      // A grant that does not persist cannot reopen the file later.
      uri: pdf.persistedRead ? pdf.uri : null,
      release: () => documents.releasePdf(pdf.leaseId),
    );
  }

  Future<void> _openFile(File file) => _openRecorded(
    path: file.path,
    displayName: file.uri.pathSegments.last,
    uri: file.uri.toString(),
  );

  Future<void> _openRecorded({
    required String path,
    required String displayName,
    String? uri,
    Future<void> Function()? release,
  }) async {
    LibraryDocument? record;
    String? identity;
    final library = widget.library;
    if (library != null) {
      try {
        identity = await widget.identify(path);
        record = await library.recordOpen(
          identity: identity,
          displayName: displayName,
          uri: uri,
        );
      } on Object catch (error) {
        // The library is a convenience: the document still opens.
        debugPrint('Doxa: cannot record $displayName: $error');
      }
    }
    if (!mounted) {
      await release?.call();
      return;
    }
    final engine = widget.engine;
    final settings = widget.settings;
    final state = record?.state;
    Future<PdfEngine>? readerEngine;
    final route = MaterialPageRoute<void>(
      builder: (_) => ReaderPage(
        engine: readerEngine ??= Future.sync(engine),
        source: FileSource(path),
        title: displayName,
        settings: settings,
        releaseSource: release,
        initialPosition: state == null
            ? null
            : (page: state.page, x: state.x, y: state.y, zoom: state.zoom),
        initialRightToLeft: state?.rightToLeft ?? false,
        onReadingState: record == null
            ? null
            : (position, rightToLeft, pageCount) => unawaited(
                library!
                    .saveState(record!.id, (
                      page: position.page,
                      x: position.x,
                      y: position.y,
                      zoom: position.zoom,
                      rightToLeft: rightToLeft,
                    ), pageCount: pageCount)
                    .catchError((Object error) {
                      debugPrint('Doxa: cannot save reading state: $error');
                    }),
              ),
        onOpened: identity == null
            ? null
            : (engine, document, info) =>
                  _thumbnail(engine, document, info, identity!),
      ),
    );
    unawaited(
      Navigator.of(context).push(route).then((_) async {
        if (readerEngine == null) await release?.call();
      }),
    );
  }

  /// Writes a missing thumbnail while the document is open.
  void _thumbnail(
    PdfEngine engine,
    DocumentHandle document,
    DocumentInfo info,
    String identity,
  ) {
    final store = widget.thumbnails;
    if (store == null || store.fileFor(identity).existsSync()) return;
    unawaited(
      writeThumbnail(
            engine: engine,
            document: document,
            info: info,
            store: store,
            identity: identity,
          )
          .then((_) {
            imageCache.evict(FileImage(store.fileFor(identity)));
            if (mounted) _thumbnailsChanged.value++;
          })
          .catchError((Object error) {
            debugPrint('Doxa: cannot write thumbnail: $error');
          }),
    );
  }

  void _showCannotReopen(LibraryDocument document) =>
      _showMessage(AppLocalizations.of(context).libraryCannotReopen);

  void _showAccessError(PdfAccessError error) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    _showMessage(switch (error) {
      PdfAccessError.missing => l10n.fileMissing,
      PdfAccessError.unreadable => l10n.fileUnreadable,
      PdfAccessError.notPdf => l10n.fileNotPdf,
      PdfAccessError.permissionLost => l10n.filePermissionLost,
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _setSearching(bool on) {
    setState(() {
      _searching = on;
      if (!on) _query.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = widget.library;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
              : Text(l10n.appTitle),
          actions: [
            if (_searching)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.libraryCloseSearch,
                onPressed: () => _setSearching(false),
              )
            else
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: l10n.librarySearch,
                onPressed: () => _setSearching(true),
              ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: l10n.settingsTitle,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(settings: widget.settings),
                ),
              ),
            ),
            if (widget.devDocumentsDir case final dir?)
              IconButton(
                icon: const Icon(Icons.developer_mode_outlined),
                tooltip: l10n.devDocumentsTitle,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(l10n.devDocumentsTitle)),
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: DevDocuments(directory: dir, onOpen: _openFile),
                      ),
                    ),
                  ),
                ),
              ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.libraryRecents),
              Tab(text: l10n.libraryFavorites),
            ],
          ),
        ),
        floatingActionButton: widget.pdfDocuments == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _picking ? null : _pick,
                icon: const Icon(Icons.folder_open),
                label: Text(l10n.openFile),
              ),
        body: TabBarView(
          children: [
            _DocumentList(
              documents: library?.watchRecents(),
              emptyMessage: l10n.libraryRecentsEmpty,
              query: _query.text,
              library: library,
              thumbnails: widget.thumbnails,
              thumbnailsChanged: _thumbnailsChanged,
              clock: widget.clock,
              onOpen: _reopen,
              showRemoveFromRecents: true,
            ),
            _DocumentList(
              documents: library?.watchFavorites(),
              emptyMessage: l10n.libraryFavoritesEmpty,
              query: _query.text,
              library: library,
              thumbnails: widget.thumbnails,
              thumbnailsChanged: _thumbnailsChanged,
              clock: widget.clock,
              onOpen: _reopen,
              showRemoveFromRecents: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// Folds case and the accents of Latin letters, for the name filter.
String _fold(String text) {
  const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final char in lower.split('')) {
    final index = from.indexOf(char);
    out.write(index < 0 ? char : to[index]);
  }
  return out.toString();
}

class _DocumentList extends StatefulWidget {
  const _DocumentList({
    required this.documents,
    required this.emptyMessage,
    required this.query,
    required this.library,
    required this.thumbnails,
    required this.thumbnailsChanged,
    required this.clock,
    required this.onOpen,
    required this.showRemoveFromRecents,
  });

  final Stream<List<LibraryDocument>>? documents;
  final String emptyMessage;
  final String query;
  final LibraryRepository? library;
  final ThumbnailStore? thumbnails;
  final ValueListenable<int> thumbnailsChanged;
  final DateTime Function() clock;
  final ValueChanged<LibraryDocument> onOpen;
  final bool showRemoveFromRecents;

  @override
  State<_DocumentList> createState() => _DocumentListState();
}

class _DocumentListState extends State<_DocumentList>
    with AutomaticKeepAliveClientMixin {
  // The stream is created once: a new stream on every build would restart
  // the query and flash the list.
  late final Stream<List<LibraryDocument>>? _documents = widget.documents;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<LibraryDocument>>(
      stream: _documents,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <LibraryDocument>[];
        final query = _fold(widget.query.trim());
        final shown = query.isEmpty
            ? all
            : [
                for (final d in all)
                  if (_fold(d.displayName).contains(query)) d,
              ];
        if (shown.isEmpty) {
          if (_documents != null && !snapshot.hasData) {
            return const SizedBox.shrink();
          }
          return _EmptyState(
            message: query.isEmpty
                ? widget.emptyMessage
                : l10n.librarySearchEmpty(widget.query.trim()),
          );
        }
        return ValueListenableBuilder(
          valueListenable: widget.thumbnailsChanged,
          builder: (context, _, _) => ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: shown.length,
            itemBuilder: (context, i) => _DocumentTile(
              document: shown[i],
              library: widget.library,
              thumbnail: widget.thumbnails?.fileFor(shown[i].identity),
              now: widget.clock(),
              onOpen: widget.onOpen,
              showRemoveFromRecents: widget.showRemoveFromRecents,
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/brand/doxa-glyph.png',
              width: 72,
              height: 72,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

enum _DocumentAction { favorite, removeFromRecents }

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.library,
    required this.thumbnail,
    required this.now,
    required this.onOpen,
    required this.showRemoveFromRecents,
  });

  final LibraryDocument document;
  final LibraryRepository? library;
  final File? thumbnail;
  final DateTime now;
  final ValueChanged<LibraryDocument> onOpen;
  final bool showRemoveFromRecents;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final when = lastReadLabel(l10n, document.lastOpenedAt, now);
    final subtitle = document.pageCount == 0
        ? when
        : '${l10n.libraryProgress(document.state.page + 1, document.pageCount, (document.progress * 100).floor())} · $when';
    final favorite = document.favorite;
    return ListTile(
      leading: _Thumbnail(file: thumbnail),
      title: Text(
        document.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle),
      onTap: () => onOpen(document),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(favorite ? Icons.star : Icons.star_border),
            color: favorite ? theme.colorScheme.primary : null,
            tooltip: favorite ? l10n.removeFromFavorites : l10n.addToFavorites,
            onPressed: () => library?.setFavorite(document.id, !favorite),
          ),
          if (showRemoveFromRecents)
            PopupMenuButton<_DocumentAction>(
              onSelected: (action) => switch (action) {
                _DocumentAction.favorite => library?.setFavorite(
                  document.id,
                  !favorite,
                ),
                _DocumentAction.removeFromRecents => library?.removeFromRecents(
                  document.id,
                ),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _DocumentAction.favorite,
                  child: Text(
                    favorite ? l10n.removeFromFavorites : l10n.addToFavorites,
                  ),
                ),
                PopupMenuItem(
                  value: _DocumentAction.removeFromRecents,
                  child: Text(l10n.removeFromRecents),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.file});

  final File? file;

  static const _size = Size(40, 56);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: _size.width,
      height: _size.height,
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.picture_as_pdf_outlined, color: scheme.outline),
    );
    final file = this.file;
    if (file == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        file,
        width: _size.width,
        height: _size.height,
        fit: BoxFit.cover,
        cacheWidth: (thumbnailWidth / 2).round(),
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

/// When a document was last read, for the home lists (FR-BOOK-002):
/// today, yesterday, a number of days for the last week, then the date.
String lastReadLabel(AppLocalizations l10n, DateTime when, DateTime now) {
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  // Calendar days, so a read late last night is "yesterday" this morning.
  // Rounding absorbs the 23- and 25-hour days of daylight saving changes.
  final days = (today.difference(day).inHours / 24).round();
  if (days <= 0) return l10n.lastReadToday;
  if (days == 1) return l10n.lastReadYesterday;
  if (days < 7) return l10n.lastReadDaysAgo(days);
  return DateFormat.yMMMd(l10n.localeName).format(when);
}
