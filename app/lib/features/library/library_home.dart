// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../src/doxa_theme.dart';
import '../dev/dev_documents.dart';
import '../dictionary/dictionary_popup.dart';
import '../reader/reader_tabs.dart';
import '../settings/app_settings.dart';
import '../settings/settings_page.dart';
import 'document_actions.dart';
import 'document_identity.dart';
import 'folder_page.dart';
import 'home_dashboard.dart';
import 'library_repository.dart';
import 'library_thumbnails.dart';
import 'selection.dart';

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
    this.openUri,
    this.pdfDocuments,
    this.devDocumentsDir,
    this.libraryFolders,
    this.documentFiles,
    this.identify = documentIdentity,
    this.clock = DateTime.now,
  });

  final Future<PdfEngine> Function() engine;
  final SettingsController settings;
  final Future<bool> Function(String uri)? openUri;

  /// Null where there is no database: documents open but are not recorded.
  final LibraryRepository? library;
  final ThumbnailStore? thumbnails;
  final PdfDocuments? pdfDocuments;
  final String? devDocumentsDir;

  /// Folder access (FR-FILE-006); the Folders tab is hidden when null.
  final LibraryFolders? libraryFolders;

  /// Rename, move and delete (FR-FILE-011); the menus leave them out when
  /// null.
  final DocumentFiles? documentFiles;
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

  final _folderCache = FolderListingCache();

  /// The open documents (FR-FILE-007); they stay open when the user goes
  /// back here, and opening a document from here adds a tab.
  final _readerTabs = ReaderTabs();
  bool _readerShown = false;

  /// Until the saved tabs are back, incoming documents wait.
  Future<void> _restoring = Future.value();

  late final DocumentActions? _actions = switch (widget.documentFiles) {
    final files? => DocumentActions(
      files: files,
      library: widget.library,
      thumbnails: widget.thumbnails,
      folders: widget.libraryFolders,
    ),
    null => null,
  };

  /// Bumped when a thumbnail is written, so the lists load it again.
  final _thumbnailsChanged = ValueNotifier<int>(0);

  bool get _hasFolders =>
      widget.library != null && widget.libraryFolders != null;

  /// The full list shown in place of the dashboard after "See all", or
  /// null for the dashboard (UX §5).
  HomeSection? _section;

  // Created once each: a new stream on every build would restart the
  // query and flash the dashboard.
  late final _dashboardRecents = widget.library?.watchRecents();
  late final _dashboardFavorites = widget.library?.watchFavorites();
  late final _dashboardFolders = _hasFolders
      ? widget.library!.watchFolders()
      : null;

  /// Documents selected in Recents or Favorites (FR-FILE-011); leaving
  /// the list clears it.
  final _selection = Selection<int, LibraryDocument>();

  /// The documents the open list shows now, for "Select all".
  var _shown = const <LibraryDocument>[];

  @override
  void initState() {
    super.initState();
    _incoming = widget.pdfDocuments?.incomingPdfs.listen((_) => _onIncoming());
    _selection.addListener(() => setState(() {}));
    _readerTabs
      ..addListener(_saveTabs)
      ..addListener(_markActiveRead);
    // Incoming documents open after the restored tabs, as new tabs.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _restoring = _restoreTabs().whenComplete(_onIncoming),
    );
  }

  @override
  void dispose() {
    unawaited(_incoming?.cancel());
    _query.dispose();
    _thumbnailsChanged.dispose();
    _readerTabs
      ..removeListener(_saveTabs)
      ..removeListener(_markActiveRead)
      ..dispose();
    _selection.dispose();
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
      await _restoring;
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

  Future<void> _addFolder() async {
    final folders = widget.libraryFolders!;
    try {
      final folder = await folders.pickFolder();
      if (folder == null) return;
      await widget.library!.addFolder(
        treeUri: folder.treeUri,
        displayName: folder.displayName,
      );
    } on Object catch (error) {
      debugPrint('Doxa: cannot add folder: $error');
      if (mounted) _showMessage(AppLocalizations.of(context).folderUnreadable);
    }
  }

  Future<void> _removeFolder(LibraryFolder folder) async {
    await widget.libraryFolders?.releaseFolder(folder.treeUri);
    await widget.library?.removeFolder(folder.id);
  }

  void _browse(LibraryFolder folder) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FolderPage(
          folders: widget.libraryFolders!,
          treeUri: folder.treeUri,
          title: folder.displayName,
          cache: _folderCache,
          actions: _actions,
          onOpen: (pdf) => unawaited(_openFromFolder(pdf)),
        ),
      ),
    );
  }

  /// Opens a PDF of a library folder through the folder's grant.
  Future<void> _openFromFolder(PlatformFolderEntry pdf) async {
    final documents = widget.pdfDocuments;
    if (documents == null) return;
    try {
      await _openPlatformPdf(
        documents,
        await documents.openPersistedPdf(pdf.uri),
      );
    } on PdfAccessException catch (error) {
      _showAccessError(error.error);
    } on Object catch (error) {
      debugPrint('Doxa: cannot open ${pdf.name}: $error');
      _showAccessError(PdfAccessError.unreadable);
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
    _readerTabs.open(
      _tab(
        // The same document opened again shows its tab.
        key: identity ?? path,
        title: displayName,
        record: record,
        source: FileSource(path),
        release: release,
      ),
    );
    _showReader();
  }

  /// A tab for a document, with what keeps the library in step: its
  /// reading state, its thumbnail and its place among the saved tabs.
  ReaderTab _tab({
    required String key,
    required String title,
    LibraryDocument? record,
    DocumentSource? source,
    Future<void> Function()? release,
    Future<LeasedSource> Function()? reopen,
  }) {
    final library = widget.library;
    final state = record?.state;
    final identity = record?.identity;
    return ReaderTab(
      key: key,
      title: title,
      source: source,
      release: release,
      reopen: reopen,
      libraryId: record?.id,
      thumbnail: identity == null ? null : widget.thumbnails?.fileFor(identity),
      position: state == null
          ? null
          : (page: state.page, x: state.x, y: state.y, zoom: state.zoom),
      rightToLeft: state?.rightToLeft ?? false,
      onReadingState: record == null || library == null
          ? null
          : (position, rightToLeft, pageCount) => unawaited(
              library
                  .saveState(record.id, (
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
                _thumbnail(engine, document, info, identity),
    );
  }

  /// Saves which documents are open in tabs (FR-FILE-007), for a restart.
  void _saveTabs() {
    final library = widget.library;
    if (library == null) return;
    final tabs = _readerTabs.tabs;
    final ids = <int>[];
    var active = 0;
    for (final (i, tab) in tabs.indexed) {
      final id = tab.libraryId;
      if (id == null) continue;
      if (i == _readerTabs.activeIndex) active = ids.length;
      ids.add(id);
    }
    unawaited(
      library.saveOpenTabs(ids, active: active).catchError((Object error) {
        debugPrint('Doxa: cannot save open tabs: $error');
      }),
    );
  }

  /// The library document of the tab shown last.
  int? _activeId;

  /// Records the shown tab's document as read now when another tab is
  /// shown, so recents and "Continue reading" follow tab switches.
  void _markActiveRead() {
    final id = _readerTabs.active?.libraryId;
    if (id == _activeId) return;
    _activeId = id;
    final library = widget.library;
    if (id == null || library == null) return;
    unawaited(
      library.markRead(id).catchError((Object error) {
        debugPrint('Doxa: cannot record the shown tab: $error');
      }),
    );
  }

  /// Opens the tabs that were open before the app last stopped; each
  /// document is reopened when its tab is first shown.
  Future<void> _restoreTabs() async {
    final library = widget.library;
    if (library == null) return;
    final ({List<LibraryDocument> documents, int active}) saved;
    try {
      saved = await library.openTabs();
    } on Object catch (error) {
      debugPrint('Doxa: cannot read open tabs: $error');
      return;
    }
    final tabs = [
      for (final document in saved.documents)
        if (_reopener(document) case final reopen?)
          _tab(
            key: document.identity,
            title: document.displayName,
            record: document,
            reopen: reopen,
          ),
    ];
    if (tabs.isEmpty || !mounted) return;
    _readerTabs.restore(tabs, active: saved.active);
    _showReader();
  }

  /// How to get [document]'s source again, or null when it cannot be.
  Future<LeasedSource> Function()? _reopener(LibraryDocument document) {
    final parsed = Uri.tryParse(document.uri ?? '');
    if (parsed == null) return null;
    if (parsed.scheme == 'file') {
      return () async => (
        source: FileSource(parsed.toFilePath()) as DocumentSource,
        release: null,
      );
    }
    final documents = widget.pdfDocuments;
    if (documents == null) return null;
    return () async {
      try {
        final pdf = await documents.openPersistedPdf(document.uri!);
        return (
          source: FileSource(pdf.path) as DocumentSource,
          release: () => documents.releasePdf(pdf.leaseId),
        );
      } on PdfAccessException catch (error) {
        if (error.error
            case PdfAccessError.missing || PdfAccessError.permissionLost) {
          await widget.library?.forgetLocation(document.id);
        }
        rethrow;
      }
    };
  }

  /// Shows the open tabs (FR-FILE-007), unless they are already shown.
  void _showReader() {
    if (_readerShown) return;
    _readerShown = true;
    final engine = widget.engine;
    Future<PdfEngine>? readerEngine;
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => ReaderWorkspace(
                tabs: _readerTabs,
                engine: readerEngine ??= Future.sync(engine),
                settings: widget.settings,
              ),
            ),
          )
          .whenComplete(() => _readerShown = false),
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

  void _selectAll() => _selection.addAll([
    for (final document in _shown) MapEntry(document.id, document),
  ]);

  /// Shows [section]'s full list, or the dashboard when null.
  void _showSection(HomeSection? section, {bool search = false}) {
    _selection.clear();
    setState(() {
      _section = section;
      _searching = search;
      _query.clear();
    });
  }

  /// Runs a batch action on the selection, then leaves selection mode.
  Future<void> _onSelected(
    Future<void> Function(List<LibraryDocument> documents) action,
  ) async {
    await action(_selection.values);
    _selection.clear();
  }

  List<Widget> _selectionActions(AppLocalizations l10n) {
    final chosen = _selection.values;
    final actions = _actions;
    final library = widget.library;
    final uris = [for (final d in chosen) d.uri];
    final authorities = {
      for (final uri in uris) Uri.tryParse(uri ?? '')?.authority,
    };
    return [
      if (_section == HomeSection.recents && library != null)
        IconButton(
          icon: const Icon(Icons.playlist_remove),
          tooltip: l10n.removeFromRecents,
          onPressed: () => _onSelected((documents) async {
            for (final d in documents) {
              await library.removeFromRecents(d.id);
            }
          }),
        ),
      if (actions != null &&
          authorities.length == 1 &&
          uris.every(actions.canMove))
        IconButton(
          icon: const Icon(Icons.drive_file_move_outlined),
          tooltip: l10n.moveDocument,
          onPressed: () => _onSelected(
            (documents) =>
                actions.moveAll(context, [for (final d in documents) d.uri!]),
          ),
        ),
      if (actions != null && uris.every(actions.canChange))
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.deleteDocument,
          onPressed: () => _onSelected(
            (documents) => actions.deleteAll(context, [
              for (final d in documents) (uri: d.uri!, name: d.displayName),
            ]),
          ),
        ),
    ];
  }

  List<Widget> _menuActions(AppLocalizations l10n) => [
    IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: l10n.settingsTitle,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              SettingsPage(settings: widget.settings, openUri: widget.openUri),
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
  ];

  Widget? _openFileButton(AppLocalizations l10n) => widget.pdfDocuments == null
      ? null
      : FloatingActionButton.extended(
          onPressed: _picking ? null : _pick,
          icon: const Icon(Icons.folder_open),
          label: Text(l10n.openFile),
        );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final section = _section;
    return PopScope(
      // Back leaves selection mode first, then the full list.
      canPop: !_selection.isActive && section == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selection.isActive) {
          _selection.clear();
        } else {
          _showSection(null);
        }
      },
      child: section == null
          ? _dashboard(l10n)
          : _sectionScaffold(l10n, section),
    );
  }

  /// The dashboard (UX §5): Continue reading, Favorites, Folders, Recents.
  Widget _dashboard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: MediaQuery.sizeOf(context).width >= 600 ? 40 : 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _BrandMark(),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                l10n.appTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: l10n.librarySearch,
            onPressed: () => _showSection(HomeSection.recents, search: true),
          ),
          const DictionaryButton(),
          ..._menuActions(l10n),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _openFileButton(l10n),
      body: HomeDashboard(
        recents: _dashboardRecents,
        favorites: _dashboardFavorites,
        folders: _dashboardFolders,
        thumbnails: widget.thumbnails,
        now: widget.clock(),
        onOpen: _reopen,
        onSeeAll: _showSection,
        onAddFolder: _hasFolders ? _addFolder : null,
        onBrowse: _hasFolders ? _browse : null,
      ),
    );
  }

  /// One section's full list, with search, sort, menus and selection.
  Widget _sectionScaffold(AppLocalizations l10n, HomeSection section) {
    final library = widget.library;
    final title = switch (section) {
      HomeSection.recents => l10n.libraryRecents,
      HomeSection.favorites => l10n.libraryFavorites,
      HomeSection.folders => l10n.libraryFolders,
    };
    return Scaffold(
      appBar: _selection.isActive
          ? selectionAppBar(
              context,
              count: _selection.length,
              onClear: _selection.clear,
              onSelectAll: _selectAll,
              actions: _selectionActions(l10n),
            )
          : AppBar(
              leading: BackButton(onPressed: () => _showSection(null)),
              title: _searching
                  ? TextField(
                      controller: _query,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: l10n.librarySearch,
                        border: InputBorder.none,
                        filled: false,
                      ),
                      onChanged: (_) => setState(() {}),
                    )
                  : Text(title),
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
                ..._menuActions(l10n),
              ],
            ),
      floatingActionButton: _openFileButton(l10n),
      body: switch (section) {
        HomeSection.recents => _DocumentList(
          key: const ValueKey(HomeSection.recents),
          documents: library?.watchRecents(),
          emptyMessage: l10n.libraryRecentsEmpty,
          query: _query.text,
          library: library,
          thumbnails: widget.thumbnails,
          thumbnailsChanged: _thumbnailsChanged,
          clock: widget.clock,
          onOpen: _reopen,
          actions: _actions,
          showRemoveFromRecents: true,
          selection: _selection,
          onShown: (shown) => _shown = shown,
        ),
        HomeSection.favorites => _DocumentList(
          key: const ValueKey(HomeSection.favorites),
          documents: library?.watchFavorites(),
          emptyMessage: l10n.libraryFavoritesEmpty,
          query: _query.text,
          library: library,
          thumbnails: widget.thumbnails,
          thumbnailsChanged: _thumbnailsChanged,
          clock: widget.clock,
          onOpen: _reopen,
          actions: _actions,
          showRemoveFromRecents: false,
          selection: _selection,
          onShown: (shown) => _shown = shown,
        ),
        HomeSection.folders => _FolderList(
          key: const ValueKey(HomeSection.folders),
          folders: library!.watchFolders(),
          query: _query.text,
          onAdd: _addFolder,
          onBrowse: _browse,
          onRemove: _removeFolder,
        ),
      },
    );
  }
}

/// The four brand strokes beside the app's name.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, color) in brandColors.indexed) ...[
        if (i > 0) const SizedBox(width: 3),
        Container(
          width: 6,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    ],
  );
}

class _DocumentList extends StatefulWidget {
  const _DocumentList({
    super.key,
    required this.documents,
    required this.emptyMessage,
    required this.query,
    required this.library,
    required this.thumbnails,
    required this.thumbnailsChanged,
    required this.clock,
    required this.onOpen,
    required this.actions,
    required this.showRemoveFromRecents,
    required this.selection,
    required this.onShown,
  });

  final Stream<List<LibraryDocument>>? documents;
  final String emptyMessage;
  final String query;
  final LibraryRepository? library;
  final ThumbnailStore? thumbnails;
  final ValueListenable<int> thumbnailsChanged;
  final DateTime Function() clock;
  final ValueChanged<LibraryDocument> onOpen;
  final DocumentActions? actions;
  final bool showRemoveFromRecents;
  final Selection<int, LibraryDocument> selection;

  /// Told the documents shown after each build, without a rebuild.
  final ValueChanged<List<LibraryDocument>> onShown;

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
        final query = foldName(widget.query.trim());
        final shown = query.isEmpty
            ? all
            : [
                for (final d in all)
                  if (foldName(d.displayName).contains(query)) d,
              ];
        widget.onShown(shown);
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
              actions: widget.actions,
              showRemoveFromRecents: widget.showRemoveFromRecents,
              selectable:
                  widget.actions != null || widget.showRemoveFromRecents,
              selecting: widget.selection.isActive,
              selected: widget.selection.contains(shown[i].id),
              onSelect: () => widget.selection.toggle(shown[i].id, shown[i]),
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

sealed class _DocumentAction {
  const _DocumentAction();
}

class _ToggleFavorite extends _DocumentAction {
  const _ToggleFavorite();
}

class _RemoveFromRecents extends _DocumentAction {
  const _RemoveFromRecents();
}

class _OnFile extends _DocumentAction {
  const _OnFile(this.action);

  final FileAction action;
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.library,
    required this.thumbnail,
    required this.now,
    required this.onOpen,
    required this.actions,
    required this.showRemoveFromRecents,
    required this.selectable,
    required this.selecting,
    required this.selected,
    required this.onSelect,
  });

  final LibraryDocument document;
  final LibraryRepository? library;
  final File? thumbnail;
  final DateTime now;
  final ValueChanged<LibraryDocument> onOpen;
  final DocumentActions? actions;
  final bool showRemoveFromRecents;

  /// Whether a long press selects the document (FR-FILE-011).
  final bool selectable;

  /// While documents are selected, a tap selects instead of opening.
  final bool selecting;
  final bool selected;
  final VoidCallback onSelect;

  void _select(BuildContext context, _DocumentAction action) {
    switch (action) {
      case _ToggleFavorite():
        unawaited(library?.setFavorite(document.id, !document.favorite));
      case _RemoveFromRecents():
        unawaited(library?.removeFromRecents(document.id));
      case _OnFile(:final action):
        unawaited(
          runFileAction(
            context,
            actions!,
            action,
            uri: document.uri!,
            name: document.displayName,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fileItems = fileActionItems<_DocumentAction>(
      l10n,
      actions,
      document.uri,
      _OnFile.new,
    );
    final when = lastReadLabel(l10n, document.lastOpenedAt, now);
    final subtitle = document.pageCount == 0
        ? when
        : '${l10n.libraryProgress(document.state.page + 1, document.pageCount, (document.progress * 100).floor())} · $when';
    final favorite = document.favorite;
    return ListTile(
      selected: selected,
      leading: SelectedMark(
        selected: selected,
        child: _Thumbnail(file: thumbnail),
      ),
      title: Text(
        document.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle),
      onTap: selecting ? onSelect : () => onOpen(document),
      onLongPress: selectable ? onSelect : null,
      trailing: selecting
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(favorite ? Icons.star : Icons.star_border),
                  color: favorite ? theme.colorScheme.primary : null,
                  tooltip: favorite
                      ? l10n.removeFromFavorites
                      : l10n.addToFavorites,
                  onPressed: () => library?.setFavorite(document.id, !favorite),
                ),
                if (showRemoveFromRecents || fileItems.isNotEmpty)
                  PopupMenuButton<_DocumentAction>(
                    onSelected: (action) => _select(context, action),
                    itemBuilder: (_) => [
                      if (showRemoveFromRecents) ...[
                        PopupMenuItem(
                          value: const _ToggleFavorite(),
                          child: Text(
                            favorite
                                ? l10n.removeFromFavorites
                                : l10n.addToFavorites,
                          ),
                        ),
                        PopupMenuItem(
                          value: const _RemoveFromRecents(),
                          child: Text(l10n.removeFromRecents),
                        ),
                      ],
                      ...fileItems,
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

class _FolderList extends StatefulWidget {
  const _FolderList({
    super.key,
    required this.folders,
    required this.query,
    required this.onAdd,
    required this.onBrowse,
    required this.onRemove,
  });

  final Stream<List<LibraryFolder>> folders;
  final String query;
  final VoidCallback onAdd;
  final ValueChanged<LibraryFolder> onBrowse;
  final ValueChanged<LibraryFolder> onRemove;

  @override
  State<_FolderList> createState() => _FolderListState();
}

class _FolderListState extends State<_FolderList>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<LibraryFolder>> _folders = widget.folders;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<LibraryFolder>>(
      stream: _folders,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final query = foldName(widget.query.trim());
        final shown = [
          for (final f in snapshot.data!)
            if (query.isEmpty || foldName(f.displayName).contains(query)) f,
        ];
        final add = ListTile(
          leading: const Icon(Icons.create_new_folder_outlined),
          title: Text(l10n.addFolder),
          onTap: widget.onAdd,
        );
        if (snapshot.data!.isEmpty) {
          return ListView(
            children: [
              add,
              _EmptyState(message: l10n.libraryFoldersEmpty),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            add,
            for (final folder in shown)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.displayName),
                onTap: () => widget.onBrowse(folder),
                trailing: PopupMenuButton<LibraryFolder>(
                  onSelected: widget.onRemove,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: folder,
                      child: Text(l10n.removeFolder),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
