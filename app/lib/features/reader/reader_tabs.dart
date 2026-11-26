// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../settings/app_settings.dart';
import 'reader_controller.dart';
import 'reader_page.dart';

/// One open document (FR-FILE-007). Only the active tab has its document
/// open in the engine; the others keep their place and nothing else, so
/// several textbooks fit the memory budget (NFR-PERF-006).
final class ReaderTab {
  ReaderTab({
    required this.key,
    required this.title,
    required this.source,
    this.release,
    this.position,
    this.rightToLeft = false,
    this.onReadingState,
    this.onOpened,
  });

  /// Identifies the document, so opening it again shows its tab.
  final String key;
  final String title;
  final DocumentSource source;

  /// Gives back the platform source once the tab is closed.
  final Future<void> Function()? release;

  /// Where the reader was the last time this tab was shown.
  ReadingPosition? position;
  bool rightToLeft;

  final ReadingStateListener? onReadingState;
  final DocumentOpenedListener? onOpened;

  /// Completes when the engine is done with the source (see [ReaderTabs]).
  Future<void> _idle = Future.value();
}

/// The open documents and which one is shown (FR-FILE-007).
final class ReaderTabs extends ChangeNotifier {
  final _tabs = <ReaderTab>[];
  int _active = -1;

  List<ReaderTab> get tabs => List.unmodifiable(_tabs);
  bool get isEmpty => _tabs.isEmpty;
  int get activeIndex => _active;
  ReaderTab? get active => _active < 0 ? null : _tabs[_active];

  /// Shows [tab]. A document that already has a tab is shown there instead,
  /// and the new source is given back.
  void open(ReaderTab tab) {
    final existing = _tabs.indexWhere((t) => t.key == tab.key);
    if (existing >= 0) {
      unawaited(tab.release?.call());
      _active = existing;
    } else {
      _tabs.add(tab);
      _active = _tabs.length - 1;
    }
    notifyListeners();
  }

  void activate(int index) {
    if (index == _active || index < 0 || index >= _tabs.length) return;
    _active = index;
    notifyListeners();
  }

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
    tab._idle.then((_) => tab.release?.call()).catchError((Object error) {
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
/// with it (`docs/plan/05-ux-design.md` §3). Pops itself when the last tab
/// closes.
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
      Navigator.of(context).maybePop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tabs.active;
    if (tab == null) return const SizedBox.shrink();
    final wide =
        MediaQuery.sizeOf(context).width >= ReaderWorkspace.tabRowWidth;
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
      source: tab.source,
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
      // Shown from the first tab, so any document can be closed here.
      tabRow: wide ? ReaderTabRow(tabs: widget.tabs) : null,
    );
  }
}

/// The row of open documents under the reader's app bar (FR-FILE-007).
class ReaderTabRow extends StatelessWidget implements PreferredSizeWidget {
  const ReaderTabRow({super.key, required this.tabs});

  final ReaderTabs tabs;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final all = tabs.tabs;
    return SizedBox(
      height: preferredSize.height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: all.length,
        itemBuilder: (context, i) {
          final active = i == tabs.activeIndex;
          return Semantics(
            selected: active,
            button: true,
            child: InkWell(
              onTap: () => tabs.activate(i),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsetsDirectional.only(start: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active ? scheme.primary : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        all[i].title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight: active ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: l10n.closeTab(all[i].title),
                      onPressed: () => tabs.close(i),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
