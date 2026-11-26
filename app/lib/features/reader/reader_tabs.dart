// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../src/doxa_theme.dart';
import '../settings/app_settings.dart';
import 'reader_controller.dart';
import 'reader_page.dart';

/// A document source and how to give it back.
typedef LeasedSource = ({
  DocumentSource source,
  Future<void> Function()? release,
});

/// One open document (FR-FILE-007). Only the active tab has its document
/// open in the engine; the others keep their place and nothing else, so
/// several textbooks fit the memory budget (NFR-PERF-006).
final class ReaderTab {
  ReaderTab({
    required this.key,
    required this.title,
    DocumentSource? source,
    this._release,
    this.reopen,
    this.libraryId,
    this.thumbnail,
    this.position,
    this.rightToLeft = false,
    this.onReadingState,
    this.onOpened,
  }) : assert(source != null || reopen != null),
       _source = source;

  /// Identifies the document, so opening it again shows its tab.
  final String key;
  final String title;

  DocumentSource? _source;
  Future<void> Function()? _release;

  /// Gets the source of a tab restored after a restart, the first time it
  /// is shown. Throws when the file can no longer be opened.
  final Future<LeasedSource> Function()? reopen;

  /// The library document, so the tab can be restored after a restart.
  final int? libraryId;

  /// The first page, for the tab switcher on phones.
  final File? thumbnail;

  /// Where the reader was the last time this tab was shown.
  ReadingPosition? position;
  bool rightToLeft;

  final ReadingStateListener? onReadingState;
  final DocumentOpenedListener? onOpened;

  /// Completes when the engine is done with the source (see [ReaderTabs]).
  Future<void> _idle = Future.value();
  Future<void>? _reopening;
}

/// The open documents and which one is shown (FR-FILE-007).
final class ReaderTabs extends ChangeNotifier {
  final _tabs = <ReaderTab>[];
  int _active = -1;

  List<ReaderTab> get tabs => List.unmodifiable(_tabs);
  bool get isEmpty => _tabs.isEmpty;
  int get length => _tabs.length;
  int get activeIndex => _active;
  ReaderTab? get active => _active < 0 ? null : _tabs[_active];

  /// Shows [tab]. A document that already has a tab is shown there instead,
  /// and the new source is given back.
  void open(ReaderTab tab) {
    final existing = _tabs.indexWhere((t) => t.key == tab.key);
    if (existing >= 0) {
      unawaited(tab._release?.call());
      _active = existing;
    } else {
      _tabs.add(tab);
      _active = _tabs.length - 1;
    }
    notifyListeners();
  }

  /// Puts back [tabs] saved before a restart, with the one at [active]
  /// shown.
  void restore(List<ReaderTab> tabs, {required int active}) {
    if (tabs.isEmpty) return;
    _tabs.addAll(tabs);
    _active = active.clamp(0, _tabs.length - 1);
    notifyListeners();
  }

  void activate(int index) {
    if (index == _active || index < 0 || index >= _tabs.length) return;
    _active = index;
    notifyListeners();
  }

  /// Moves the tab at [from] so it ends up at [to]; the shown tab stays
  /// shown.
  void move(int from, int to) {
    if (from == to) return;
    final shown = active;
    _tabs.insert(to, _tabs.removeAt(from));
    _active = shown == null ? -1 : _tabs.indexOf(shown);
    notifyListeners();
  }

  /// Gets the source of a restored [tab] (see [ReaderTab.reopen]).
  Future<void> acquire(ReaderTab tab) =>
      tab._reopening ??= tab.reopen!().then((leased) {
        tab
          .._source = leased.source
          .._release = leased.release;
        // Closed while it was being reopened.
        if (!_tabs.contains(tab)) _release(tab);
      });

  /// Closes the tab at [index]; the tab to its left is shown next when the
  /// closed one was active, as browsers do.
  void close(int index) {
    final tab = _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _active = -1;
    } else if (index < _active || (index == _active && index > 0)) {
      _active--;
    }
    notifyListeners();
    _release(tab);
  }

  /// Gives back the source once the engine has closed the document.
  void _release(ReaderTab tab) => unawaited(
    tab._idle.then((_) => tab._release?.call()).catchError((Object error) {
      debugPrint('Doxa: cannot release ${tab.title}: $error');
    }),
  );

  /// Gives back every tab's source, without telling listeners: the screens
  /// that showed the tabs are going away too.
  @override
  void dispose() {
    _tabs.forEach(_release);
    _tabs.clear();
    _active = -1;
    super.dispose();
  }
}

/// The reader with its tabs (FR-FILE-007): the active tab's document, and
/// on medium and expanded widths a row of tabs under the app bar that hides
/// with it (`docs/plan/05-ux-design.md` §3). Phones get a button that opens
/// a grid of the tabs instead. Pops itself when the last tab closes.
class ReaderWorkspace extends StatefulWidget {
  const ReaderWorkspace({
    super.key,
    required this.tabs,
    required this.engine,
    this.settings,
  });

  final ReaderTabs tabs;
  final Future<PdfEngine> engine;
  final SettingsController? settings;

  /// Widths from which tabs show as a row (Material medium size class).
  static const tabRowWidth = 600.0;

  @override
  State<ReaderWorkspace> createState() => _ReaderWorkspaceState();
}

class _ReaderWorkspaceState extends State<ReaderWorkspace> {
  /// For each tab shown, completes once its page's engine work is done.
  final _shown = <ReaderTab, Completer<void>>{};

  @override
  void initState() {
    super.initState();
    widget.tabs.addListener(_onTabs);
  }

  @override
  void dispose() {
    widget.tabs.removeListener(_onTabs);
    super.dispose();
  }

  void _onTabs() {
    if (!mounted) return;
    if (widget.tabs.isEmpty) {
      // Leaves the reader, and the tab switcher if it is on top.
      final route = ModalRoute.of(context);
      Navigator.of(context)
        ..popUntil((r) => r == route)
        ..maybePop();
    } else {
      setState(() {});
    }
  }

  /// Tabs whose source is being reopened.
  final _acquiring = <ReaderTab>{};

  /// Gets a restored tab's source; a file that is gone closes its tab.
  void _acquire(ReaderTab tab) {
    if (!_acquiring.add(tab)) return;
    unawaited(
      widget.tabs
          .acquire(tab)
          .then((_) {
            _acquiring.remove(tab);
            if (mounted) setState(() {});
          })
          .catchError((Object error) {
            _acquiring.remove(tab);
            debugPrint('Doxa: cannot reopen ${tab.title}: $error');
            final index = widget.tabs.tabs.indexOf(tab);
            if (index < 0 || !mounted) return;
            final messenger = ScaffoldMessenger.of(context);
            final message = AppLocalizations.of(context).libraryCannotReopen;
            widget.tabs.close(index);
            messenger.showSnackBar(SnackBar(content: Text(message)));
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tabs.active;
    if (tab == null) return const SizedBox.shrink();
    final wide =
        MediaQuery.sizeOf(context).width >= ReaderWorkspace.tabRowWidth;
    // Shown from the first tab, so any document can be closed here.
    final tabRow = wide ? ReaderTabRow(tabs: widget.tabs) : null;
    final tabsButton = wide ? null : _TabsButton(tabs: widget.tabs);
    final source = tab._source;
    if (source == null) {
      _acquire(tab);
      return Scaffold(
        appBar: AppBar(
          title: Text(tab.title, overflow: TextOverflow.ellipsis),
          bottom: tabRow,
          actions: [?tabsButton],
        ),
        body: Center(
          child: Semantics(
            label: AppLocalizations.of(context).readerOpening,
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }
    final idle = _shown.putIfAbsent(tab, () {
      final idle = Completer<void>();
      tab._idle = idle.future;
      return idle;
    });
    return ReaderPage(
      // A new page per tab: the old one saves its place and closes its
      // document, so only the active tab holds pages in memory.
      key: ObjectKey(tab),
      engine: widget.engine,
      source: source,
      title: tab.title,
      settings: widget.settings,
      initialPosition: tab.position,
      initialRightToLeft: tab.rightToLeft,
      // Called once the engine has closed the document; the tab releases
      // its source itself when it closes.
      releaseSource: () async {
        _shown.remove(tab);
        if (!idle.isCompleted) idle.complete();
      },
      onReadingState: (position, rightToLeft, pageCount) {
        tab
          ..position = position
          ..rightToLeft = rightToLeft;
        tab.onReadingState?.call(position, rightToLeft, pageCount);
      },
      onOpened: tab.onOpened,
      onGiveUp: () => widget.tabs.close(widget.tabs.tabs.indexOf(tab)),
      tabRow: tabRow,
      tabsButton: tabsButton,
    );
  }
}

/// The row of open documents under the reader's app bar (FR-FILE-007).
/// A long press drags a tab to another place.
class ReaderTabRow extends StatelessWidget implements PreferredSizeWidget {
  const ReaderTabRow({super.key, required this.tabs});

  final ReaderTabs tabs;

  @override
  Size get preferredSize => const Size.fromHeight(42);

  /// A document's colour among the brand colours, the same for its tab
  /// wherever the tab moves.
  static Color colorOf(ReaderTab tab) =>
      brandColors[tab.key.codeUnits.fold(0, (a, b) => a + b) %
          brandColors.length];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The active tab takes the colour behind the page, so it joins it.
    final page = theme.brightness == Brightness.dark
        ? scheme.surfaceContainerLowest
        : scheme.surfaceContainerHigh;
    final all = tabs.tabs;
    return SizedBox(
      height: preferredSize.height,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        buildDefaultDragHandles: false,
        itemCount: all.length,
        onReorderItem: tabs.move,
        itemBuilder: (context, i) {
          final active = i == tabs.activeIndex;
          return ReorderableDelayedDragStartListener(
            key: ObjectKey(all[i]),
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 2),
              child: Semantics(
                selected: active,
                button: true,
                child: Material(
                  color: active ? page : scheme.surfaceContainer,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => tabs.activate(i),
                    child: Container(
                      width: 220,
                      padding: const EdgeInsetsDirectional.only(start: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: active
                                ? colorOf(all[i])
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              all[i].title,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: active
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: l10n.closeTab(all[i].title),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => tabs.close(i),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The phone's way to the other tabs (FR-FILE-007): how many are open;
/// opens [TabSwitcher].
class _TabsButton extends StatelessWidget {
  const _TabsButton({required this.tabs});

  final ReaderTabs tabs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = tabs.length;
    return IconButton(
      tooltip: l10n.openTabs(count),
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => TabSwitcher(tabs: tabs))),
      icon: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.crop_square),
          Text(
            count > 99 ? '99+' : '$count',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// The open tabs as a grid of first pages, for phones (FR-FILE-007,
/// maintainer decision 2026-11-26). A tap shows the tab; ✕ closes it.
class TabSwitcher extends StatelessWidget {
  const TabSwitcher({super.key, required this.tabs});

  final ReaderTabs tabs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: tabs,
      builder: (context, _) {
        final all = tabs.tabs;
        return Scaffold(
          appBar: AppBar(title: Text(l10n.openTabs(all.length))),
          body: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.62,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
            ),
            itemCount: all.length,
            itemBuilder: (context, i) => _TabCard(
              tab: all[i],
              active: i == tabs.activeIndex,
              onOpen: () {
                tabs.activate(i);
                Navigator.of(context).pop();
              },
              onClose: () => tabs.close(i),
            ),
          ),
        );
      },
    );
  }
}

class _TabCard extends StatelessWidget {
  const _TabCard({
    required this.tab,
    required this.active,
    required this.onOpen,
    required this.onClose,
  });

  final ReaderTab tab;
  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.picture_as_pdf_outlined,
          size: 40,
          color: scheme.outline,
        ),
      ),
    );
    final thumbnail = tab.thumbnail;
    return Semantics(
      selected: active,
      button: true,
      label: tab.title,
      child: Card.outlined(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: active ? scheme.primary : scheme.outlineVariant,
            width: active ? 3 : 1,
          ),
        ),
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumbnail == null)
                      placeholder
                    else
                      Image.file(
                        thumbnail,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => placeholder,
                      ),
                    Align(
                      alignment: AlignmentDirectional.topEnd,
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.close),
                        tooltip: l10n.closeTab(tab.title),
                        onPressed: onClose,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  tab.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: active ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
