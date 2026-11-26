// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../dictionary/dictionary_library.dart';
import '../dictionary/dictionary_popup.dart';
import '../settings/app_settings.dart';
import '../settings/settings_page.dart';
import 'color_mode.dart';
import 'frame_probe.dart';
import 'navigation_panel.dart';
import 'reader_controller.dart';
import 'reader_geometry.dart';
import 'reader_view.dart';
import 'search_session.dart';
import 'text_selection.dart';

/// Opens external links in another app; injectable for tests.
typedef UriOpener = Future<bool> Function(String uri);

Future<bool> _openWithPlatform(String uri) => DoxaPlatform().openUri(uri);

Future<void> _keepScreenOnWithPlatform(bool keepOn) =>
    DoxaPlatform().setKeepScreenOn(keepOn);

/// Receives where the reader is (FR-VIEW-006): the position, the
/// per-document right-to-left order (FR-VIEW-019) and the page count.
typedef ReadingStateListener = void Function(
  ReadingPosition position,
  bool rightToLeft,
  int pageCount,
);

/// Called once the document is open, with what is needed to render it
/// (for example a library thumbnail).
typedef DocumentOpenedListener = void Function(
  PdfEngine engine,
  DocumentHandle document,
  DocumentInfo info,
);

/// Opens a document and shows it in the reader (issues #47, #48, #52).
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.engine,
    required this.source,
    required this.title,
    this.decoder = decodeBitmap,
    this.openUri = _openWithPlatform,
    this.settings,
    this.releaseSource,
    this.keepScreenOn = _keepScreenOnWithPlatform,
    this.initialPosition,
    this.initialRightToLeft = false,
    this.onReadingState,
    this.onOpened,
    this.tabRow,
    this.onGiveUp,
    this.tabsButton,
  });

  final Future<PdfEngine> engine;
  final DocumentSource source;
  final String title;

  /// Releases a platform source after its last engine operation.
  final Future<void> Function()? releaseSource;
  final BitmapDecoder decoder;
  final UriOpener openUri;

  /// App settings for page colours, layout defaults, and screen wake lock.
  final SettingsController? settings;

  /// Keeps the screen on or lets it sleep (FR-VIEW-013); injectable.
  final Future<void> Function(bool keepOn) keepScreenOn;

  /// Where to open the document, and in which page order (FR-VIEW-006).
  final ReadingPosition? initialPosition;
  final bool initialRightToLeft;

  /// Called a moment after the page changes, when the app goes to the
  /// background, and when the reader closes.
  final ReadingStateListener? onReadingState;
  final DocumentOpenedListener? onOpened;

  /// The open documents (FR-FILE-007), shown under the app bar and hidden
  /// with it.
  final PreferredSizeWidget? tabRow;

  /// Closes the document when the user gives up opening it (a cancelled
  /// password prompt). Without it, the page's route is removed.
  final VoidCallback? onGiveUp;

  /// Opens the other tabs on phones (FR-FILE-007); first in the app bar.
  final Widget? tabsButton;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

enum _Failure { password, wrongPassword, cancelled, open, unreadable, format }

class _ReaderPageState extends State<ReaderPage> {
  PdfEngine? _engine;
  ReaderController? _controller;
  SearchSession? _search;
  TextSelectionController? _selection;
  bool _searchOpen = false;

  PageColorMode _localColorMode = PageColorMode.normal;

  /// Full screen (FR-VIEW-012): toolbars and system bars hidden; a tap in
  /// the middle of the page shows the toolbars until the next tap.
  bool _fullscreen = false;
  bool _barsShown = true;
  bool _keptScreenOn = false;
  _Failure? _failure;
  late Future<void> _opening;
  bool _promptPending = false;
  final FrameProbe? _probe = kReleaseMode ? null : FrameProbe();
  Timer? _saveTimer;
  late final AppLifecycleListener _lifecycle;

  /// How long the page must stay the same before its state is saved.
  static const _saveDelay = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _saveReadingState);
    _opening = _open();
    widget.settings?.addListener(_onSettings);
    _applyKeepScreenOn();
  }

  /// Settings can change while the document is open (custom colours from
  /// the view options, keep screen on).
  void _onSettings() {
    _applyKeepScreenOn();
    if (mounted) setState(() {});
  }

  /// Follows the keep-screen-on setting while the document is open.
  void _applyKeepScreenOn() {
    final on = widget.settings?.value.keepScreenOn ?? false;
    if (on == _keptScreenOn) return;
    _keptScreenOn = on;
    unawaited(widget.keepScreenOn(on));
  }

  void _setFullscreen(bool on) {
    setState(() {
      _fullscreen = on;
      _barsShown = !on;
    });
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  /// A tap on the page away from links and edge zones.
  void _onPageTap() {
    if (_fullscreen) setState(() => _barsShown = !_barsShown);
  }

  Future<void> _open([String? password]) async {
    OpenResult result;
    PdfEngine engine;
    try {
      engine = await widget.engine;
      if (!mounted) return;
      result = await engine.open(widget.source, password: password);
    } on Object catch (error) {
      debugPrint('Doxa: cannot open ${widget.title}: $error');
      if (mounted) setState(() => _failure = _Failure.open);
      return;
    }
    if (!mounted) {
      if (result is DocumentOpened) await engine.close(result.handle);
      return;
    }
    setState(() {
      _engine = engine;
      switch (result) {
        case DocumentOpened(:final handle, :final info):
          final settings = widget.settings?.value ?? const AppSettings();
          final controller = ReaderController(
            engine: engine,
            document: handle,
            info: info,
            decoder: widget.decoder,
            options: ReaderOptions(
              mode: settings.readerMode,
              coverPage: settings.coverPage,
              rightToLeft: widget.initialRightToLeft,
              tapZones: settings.tapZones,
              keepZoomOnTurn: settings.keepZoomOnTurn,
            ),
            initialPosition: widget.initialPosition,
          );
          controller.page.addListener(_scheduleSave);
          widget.onOpened?.call(engine, handle, info);
          _controller = controller;
          _search = SearchSession(controller);
          _selection = TextSelectionController(controller);
        case PasswordRequired():
          _failure = _Failure.password;
        case WrongPassword():
          _failure = _Failure.wrongPassword;
        case OpenFailed(:final reason):
          _failure = switch (reason) {
            OpenFailure.file => _Failure.unreadable,
            OpenFailure.format => _Failure.format,
            _ => _Failure.open,
          };
      }
    });
  }

  Future<void> _askForPassword() async {
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context)!;
    _promptPending = true;
    final password = await showDialog<String>(
      context: context,
      builder: (_) =>
          _PasswordDialog(wrong: _failure == _Failure.wrongPassword),
    );
    if (!mounted) return;
    _promptPending = false;
    if (password == null) {
      if (widget.onGiveUp case final giveUp?) {
        giveUp();
      } else if (route.isFirst) {
        setState(() => _failure = _Failure.cancelled);
      } else {
        navigator.removeRoute(route);
      }
      return;
    }
    setState(() => _failure = null);
    _opening = _open(password);
  }

  Future<void> _closeSource(ReaderController? controller) async {
    try {
      await _opening;
      if (controller != null) await _engine?.close(controller.document);
    } finally {
      await widget.releaseSource?.call();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _saveReadingState);
  }

  void _saveReadingState() {
    _saveTimer?.cancel();
    final controller = _controller;
    final listener = widget.onReadingState;
    final position = controller?.position;
    if (controller == null || listener == null || position == null) return;
    listener(
      position,
      controller.options.rightToLeft,
      controller.info.pageCount,
    );
  }

  @override
  void dispose() {
    _saveReadingState();
    _lifecycle.dispose();
    _search?.dispose();
    _selection?.dispose();
    final controller = _controller;
    controller?.dispose();
    unawaited(
      _closeSource(controller).catchError((Object error) {
        debugPrint('Doxa: cannot close ${widget.title}: $error');
      }),
    );
    _probe?.dispose();
    widget.settings?.removeListener(_onSettings);
    if (_keptScreenOn) unawaited(widget.keepScreenOn(false));
    if (_fullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  /// Follows a tapped link or outline entry (FR-VIEW-010).
  Future<void> _follow(LinkTarget target) async {
    final controller = _controller;
    if (controller == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (target) {
      case GoToTarget(:final destination):
        await controller.goToDestination(destination);
      case UriTarget(:final uri):
        final choice = await showDialog<_LinkChoice>(
          context: context,
          builder: (context) => _ConfirmLink(uri: uri),
        );
        switch (choice) {
          case _LinkChoice.open:
            bool opened;
            try {
              opened = await widget.openUri(uri);
            } on Object catch (error) {
              debugPrint('Doxa: cannot open $uri: $error');
              opened = false;
            }
            if (!opened) {
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.linkOpenFailed)),
              );
            }
          case _LinkChoice.copy:
            await Clipboard.setData(ClipboardData(text: uri));
            messenger.showSnackBar(SnackBar(content: Text(l10n.linkCopied)));
          case null:
            break;
        }
      case UnsupportedTarget():
        messenger.showSnackBar(SnackBar(content: Text(l10n.linkUnsupported)));
    }
  }

  Future<void> _goToPage(ReaderController controller) async {
    final page = await showDialog<int>(
      context: context,
      builder: (context) => _GoToPageDialog(controller: controller),
    );
    if (page != null) controller.goToPage(page, record: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (ModalRoute.isCurrentOf(context) == true &&
        (_failure == _Failure.password || _failure == _Failure.wrongPassword) &&
        !_promptPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_promptPending &&
            ModalRoute.of(context)?.isCurrent == true) {
          unawaited(_askForPassword());
        }
      });
    }
    final controller = _controller;
    final settings = widget.settings?.value;
    final colorMode = settings?.colorMode ?? _localColorMode;
    final showBars = !_fullscreen || _barsShown || _searchOpen;
    final body = Scaffold(
      // In full screen the page keeps its size while the bars come and go:
      // the bars are drawn over it instead of resizing it.
      extendBodyBehindAppBar: _fullscreen,
      extendBody: _fullscreen,
      drawer: controller == null || controller.info.pageCount == 0
          ? null
          : NavigationPanel(
              controller: controller,
              onFollow: (target) {
                Navigator.of(context).pop();
                unawaited(_follow(target));
              },
            ),
      appBar: !showBars
          ? null
          : _searchOpen && _search != null
          ? _SearchBar(
              session: _search!,
              onClose: () => setState(() {
                _search!.close();
                _searchOpen = false;
              }),
            )
          : AppBar(
              // The contents button opens the drawer; no extra menu button.
              automaticallyImplyLeading: false,
              leading: Navigator.of(context).canPop()
                  ? const BackButton()
                  : null,
              title: Text(widget.title, overflow: TextOverflow.ellipsis),
              bottom: widget.tabRow,
              actions: [
                ?widget.tabsButton,
                if (controller != null && controller.info.pageCount > 0) ...[
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.toc),
                      tooltip: l10n.navigationPanel,
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  _HistoryButtons(controller: controller),
                  _PageIndicator(
                    controller: controller,
                    onPressed: () => _goToPage(controller),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: l10n.searchTooltip,
                    onPressed: () => setState(() => _searchOpen = true),
                  ),
                  _ZoomMenu(controller: controller),
                  IconButton(
                    icon: const Icon(Icons.chrome_reader_mode_outlined),
                    tooltip: l10n.viewOptions,
                    onPressed: () => showViewOptions(
                      context,
                      controller,
                      colorMode: colorMode,
                      onColorMode: settings == null
                          ? (mode) => setState(() => _localColorMode = mode)
                          : null,
                      settings: widget.settings,
                      fullscreen: _fullscreen,
                      onFullscreen: _setFullscreen,
                    ),
                  ),
                ],
              ],
            ),
      bottomNavigationBar:
          !showBars || controller == null || controller.info.pageCount < 2
          ? null
          : _PageScrubber(controller: controller),
      body: switch ((controller, _failure)) {
        (final ReaderController c, _) => Stack(
          children: [
            Positioned.fill(
              child: ReaderView(
                controller: c,
                probe: _probe,
                onLink: _follow,
                onTap: _onPageTap,
                selection: _selection,
                colorFilter: pageColorFilter(
                  colorMode,
                  background:
                      settings?.customBackground ?? defaultCustomBackground,
                  text: settings?.customText ?? defaultCustomText,
                ),
                sheetColor: sheetColor(
                  colorMode,
                  background:
                      settings?.customBackground ?? defaultCustomBackground,
                ),
              ),
            ),
            if (_selection case final selection?)
              Positioned.fill(
                child: _SelectionBar(selection: selection, reader: c),
              ),
          ],
        ),
        (_, _Failure.password || _Failure.wrongPassword) =>
          const SizedBox.shrink(),
        (_, _Failure.cancelled) => _Message(l10n.readerPasswordNeeded),
        (_, _Failure.unreadable) => _Message(l10n.fileUnreadable),
        (_, _Failure.format) => _Message(l10n.fileNotPdf),
        (_, _Failure.open) => _Message(l10n.readerOpenFailed),
        _ => Center(
          child: Semantics(
            label: l10n.readerOpening,
            child: const CircularProgressIndicator(),
          ),
        ),
      },
    );
    if (controller == null) return body;
    // Back closes search first, then leaves the document. Jumps (FR-VIEW-011)
    // are undone only with the history buttons: walking back through them
    // first sent readers to page 1 when they wanted to leave (maintainer
    // decision after the tablet check of #50).
    return PopScope(
      canPop: !_searchOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_searchOpen) return;
        setState(() {
          _search?.close();
          _searchOpen = false;
        });
      },
      child: body,
    );
  }
}

/// Back and forward through link and outline jumps (FR-VIEW-011).
class _HistoryButtons extends StatelessWidget {
  const _HistoryButtons({required this.controller});
  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: controller.history,
      builder: (context, _, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.canGoBack)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: l10n.historyBack,
              onPressed: controller.goBack,
            ),
          if (controller.canGoForward)
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: l10n.historyForward,
              onPressed: controller.goForward,
            ),
        ],
      ),
    );
  }
}

/// The current page with its label (FR-VIEW-014); opens "Go to page".
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.controller, required this.onPressed});
  final ReaderController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: controller.page,
      builder: (context, page, _) => TextButton(
        onPressed: onPressed,
        child: Text(pageIndicatorText(l10n, controller, page)),
      ),
    );
  }
}

/// "iv (4 of 120)" when the page has a label, else "4 of 120".
String pageIndicatorText(
  AppLocalizations l10n,
  ReaderController controller,
  int page,
) {
  final count = controller.info.pageCount;
  final label = controller.info.pageLabels[page];
  return label == null || label == '${page + 1}'
      ? l10n.pageOfCount(page + 1, count)
      : l10n.pageLabelOfCount(label, page + 1, count);
}

/// A page slider whose thumb shows the page label (FR-VIEW-009).
class _PageScrubber extends StatefulWidget {
  const _PageScrubber({required this.controller});
  final ReaderController controller;

  @override
  State<_PageScrubber> createState() => _PageScrubberState();
}

class _PageScrubberState extends State<_PageScrubber> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final last = controller.info.pageCount - 1;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 56,
        child: ValueListenableBuilder(
          valueListenable: controller.page,
          builder: (context, page, _) {
            final value = _dragging ?? page.toDouble();
            return Slider(
              value: value.clamp(0, last.toDouble()),
              max: last.toDouble(),
              divisions: last,
              label: controller.pageLabel(value.round()),
              onChanged: (v) => setState(() => _dragging = v),
              onChangeEnd: (v) {
                setState(() => _dragging = null);
                controller.goToPage(v.round(), record: true);
              },
            );
          },
        ),
      ),
    );
  }
}

/// "Go to page" (FR-VIEW-009): accepts a page label or a page number.
class _GoToPageDialog extends StatefulWidget {
  const _GoToPageDialog({required this.controller});
  final ReaderController controller;

  @override
  State<_GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<_GoToPageDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final page = widget.controller.parsePageInput(_text.text);
    if (page == null) {
      setState(() {
        _error = AppLocalizations.of(context).goToPageInvalid(_text.text);
      });
    } else {
      Navigator.of(context).pop(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.goToPageTitle),
      content: TextField(
        controller: _text,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.goToPageHint(widget.controller.info.pageCount),
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.goToPageAction)),
      ],
    );
  }
}

enum _LinkChoice { open, copy }

/// Confirms before an external link leaves the app (FR-VIEW-010).
class _ConfirmLink extends StatelessWidget {
  const _ConfirmLink({required this.uri});
  final String uri;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.linkOpenTitle),
      content: SelectableText(uri),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_LinkChoice.copy),
          child: Text(l10n.linkCopy),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_LinkChoice.open),
          child: Text(l10n.linkOpen),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

/// Fit width, fit page and zoom presets (FR-VIEW-004).
class _ZoomMenu extends StatelessWidget {
  const _ZoomMenu({required this.controller});
  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<void Function()>(
      icon: const Icon(Icons.zoom_in),
      tooltip: l10n.readerZoomMenu,
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: controller.fitWidth,
          child: Text(l10n.readerFitWidth),
        ),
        PopupMenuItem(
          value: controller.fitPage,
          child: Text(l10n.readerFitPage),
        ),
        for (final factor in const [2, 4])
          PopupMenuItem(
            value: () => controller.zoomTo(factor.toDouble()),
            child: Text(l10n.readerZoomFactor(factor)),
          ),
      ],
    );
  }
}

/// View options (docs/plan/05-ux-design.md §2): the page layout and how
/// pages turn (FR-VIEW-002, FR-VIEW-003, FR-VIEW-017..019).
Future<void> showViewOptions(
  BuildContext context,
  ReaderController controller, {
  PageColorMode colorMode = PageColorMode.normal,
  ValueChanged<PageColorMode>? onColorMode,
  bool fullscreen = false,
  ValueChanged<bool>? onFullscreen,
  SettingsController? settings,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => _ViewOptions(
    controller: controller,
    colorMode: colorMode,
    onColorMode: onColorMode,
    fullscreen: fullscreen,
    onFullscreen: onFullscreen,
    settings: settings,
  ),
);

class _ViewOptions extends StatefulWidget {
  const _ViewOptions({
    required this.controller,
    required this.colorMode,
    required this.onColorMode,
    required this.fullscreen,
    required this.onFullscreen,
    required this.settings,
  });
  final ReaderController controller;
  final SettingsController? settings;
  final PageColorMode colorMode;
  final ValueChanged<PageColorMode>? onColorMode;
  final bool fullscreen;
  final ValueChanged<bool>? onFullscreen;

  @override
  State<_ViewOptions> createState() => _ViewOptionsState();
}

class _ViewOptionsState extends State<_ViewOptions> {
  ReaderOptions get _options => widget.controller.options;
  late PageColorMode _colorMode = widget.colorMode;
  late bool _fullscreen = widget.fullscreen;

  void _set(ReaderOptions options) {
    final previous = _options;
    if (options == previous) return;
    setState(() => widget.controller.setOptions(options));
    final settings = widget.settings;
    settings?.update(
      settings.value.copyWith(
        readerMode: options.mode == previous.mode ? null : options.mode,
        coverPage: options.coverPage == previous.coverPage
            ? null
            : options.coverPage,
        tapZones: options.tapZones == previous.tapZones
            ? null
            : options.tapZones,
        keepZoomOnTurn: options.keepZoomOnTurn == previous.keepZoomOnTurn
            ? null
            : options.keepZoomOnTurn,
      ),
    );
  }

  Widget _colorOptions(
    PageColorMode mode,
    ValueChanged<PageColorMode> onChanged,
  ) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(title: Text(l10n.viewPageColors)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: PageColorModeSelector(mode: mode, onChanged: onChanged),
        ),
        if (mode == PageColorMode.custom)
          if (widget.settings case final settings?)
            CustomColorsEditor(settings: settings),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mode = _options.mode;
    final modes = [
      (ReaderMode.continuous, Icons.view_day_outlined, l10n.layoutContinuous),
      (ReaderMode.singlePage, Icons.crop_portrait, l10n.layoutSinglePage),
      (ReaderMode.twoPages, Icons.menu_book_outlined, l10n.layoutTwoPages),
      (ReaderMode.horizontal, Icons.view_week_outlined, l10n.layoutHorizontal),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l10n.viewOptions,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (widget.settings case final settings?)
              ValueListenableBuilder<AppSettings>(
                valueListenable: settings,
                builder: (context, value, child) => _colorOptions(
                  value.colorMode,
                  (mode) =>
                      settings.update(settings.value.copyWith(colorMode: mode)),
                ),
              )
            else if (widget.onColorMode case final onColorMode?)
              _colorOptions(_colorMode, (mode) {
                setState(() => _colorMode = mode);
                onColorMode(mode);
              }),
            if (widget.onFullscreen case final onFullscreen?)
              SwitchListTile(
                secondary: const Icon(Icons.fullscreen),
                title: Text(l10n.viewFullscreen),
                subtitle: Text(l10n.viewFullscreenHint),
                value: _fullscreen,
                onChanged: (on) {
                  setState(() => _fullscreen = on);
                  onFullscreen(on);
                },
              ),
            const Divider(),
            RadioGroup<ReaderMode>(
              groupValue: mode,
              onChanged: (value) {
                if (value != null) _set(_options.copyWith(mode: value));
              },
              child: Column(
                children: [
                  for (final (value, icon, label) in modes)
                    RadioListTile<ReaderMode>(
                      value: value,
                      secondary: Icon(icon),
                      title: Text(label),
                    ),
                ],
              ),
            ),
            const Divider(),
            SwitchListTile(
              title: Text(l10n.optionCoverPage),
              value: _options.coverPage,
              onChanged: mode == ReaderMode.twoPages
                  ? (value) => _set(_options.copyWith(coverPage: value))
                  : null,
            ),
            SwitchListTile(
              title: Text(l10n.optionRightToLeft),
              value: _options.rightToLeft,
              onChanged: mode == ReaderMode.continuous
                  ? null
                  : (value) => setState(
                      () => widget.controller.setOptions(
                        _options.copyWith(rightToLeft: value),
                      ),
                    ),
            ),
            SwitchListTile(
              title: Text(l10n.optionTapZones),
              value: _options.tapZones,
              onChanged: _options.paged
                  ? (value) => _set(_options.copyWith(tapZones: value))
                  : null,
            ),
            SwitchListTile(
              title: Text(l10n.optionKeepZoom),
              value: _options.keepZoomOnTurn,
              onChanged: _options.paged
                  ? (value) => _set(_options.copyWith(keepZoomOnTurn: value))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// The search bar (FR-TEXT-001, FR-TEXT-002): query, options, result count
/// and next/previous.
class _SearchBar extends StatefulWidget implements PreferredSizeWidget {
  const _SearchBar({required this.session, required this.onClose});
  final SearchSession session;
  final VoidCallback onClose;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _text = TextEditingController();
  bool _matchCase = false;
  bool _wholeWord = false;
  bool _ignoreDiacritics = true;

  SearchQuery get _query => SearchQuery(
    _text.text,
    matchCase: _matchCase,
    wholeWord: _wholeWord,
    ignoreDiacritics: _ignoreDiacritics,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _statusText(AppLocalizations l10n, SearchStatus status) {
    if (status.count == 0) {
      return status.searching ? l10n.searchSearching : l10n.searchNoResults;
    }
    // Before a hit on or after the start page arrives, only count.
    final count = status.current < 0
        ? l10n.searchResults(status.count)
        : l10n.searchCount(status.current + 1, status.count);
    return status.searching ? '$count…' : count;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = widget.session;
    return AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l10n.searchClose,
        onPressed: widget.onClose,
      ),
      title: TextField(
        controller: _text,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: l10n.searchHint,
          border: InputBorder.none,
        ),
        onChanged: (_) => session.update(_query),
        onSubmitted: (_) {
          // Enter steps through the hits of this query, or starts it now.
          if (session.isStale(_query)) {
            session.start(_query);
          } else {
            session.next();
          }
        },
      ),
      actions: [
        ValueListenableBuilder(
          valueListenable: session.status,
          builder: (context, status, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status.active)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(_statusText(l10n, status)),
                ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                tooltip: l10n.searchPrevious,
                onPressed: status.count == 0 ? null : session.previous,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                tooltip: l10n.searchNext,
                onPressed: status.count == 0 ? null : session.next,
              ),
            ],
          ),
        ),
        PopupMenuButton<int>(
          icon: const Icon(Icons.tune),
          tooltip: l10n.searchOptions,
          onSelected: (option) {
            setState(() {
              switch (option) {
                case 0:
                  _matchCase = !_matchCase;
                case 1:
                  _wholeWord = !_wholeWord;
                case 2:
                  _ignoreDiacritics = !_ignoreDiacritics;
              }
            });
            session.start(_query);
          },
          itemBuilder: (context) => [
            CheckedPopupMenuItem(
              value: 0,
              checked: _matchCase,
              child: Text(l10n.searchMatchCase),
            ),
            CheckedPopupMenuItem(
              value: 1,
              checked: _wholeWord,
              child: Text(l10n.searchWholeWord),
            ),
            CheckedPopupMenuItem(
              value: 2,
              checked: _ignoreDiacritics,
              child: Text(l10n.searchIgnoreDiacritics),
            ),
          ],
        ),
      ],
    );
  }
}

/// Actions for selected text (FR-TEXT-004), floating next to the
/// selection as on Android: above it, or below it when there is no room
/// above. It follows the selection while the view pans and zooms. M2 adds
/// markup here.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.selection, required this.reader});
  final TextSelectionController selection;
  final ReaderController reader;

  Future<void> _copy(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: selection.text));
    selection.clear();
    messenger.showSnackBar(SnackBar(content: Text(l10n.selectionCopied)));
  }

  /// Looks the selection up in the dictionaries (FR-TEXT-008).
  void _lookUp(BuildContext context, DictionaryScope scope) {
    final query = selection.text;
    selection.clear();
    unawaited(
      showDictionaryLookup(
        context,
        query: query,
        library: scope.library,
        lookup: scope.lookup,
        openUri: scope.openUri,
        importer: scope.importer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: selection.selection,
      builder: (context, selected, _) {
        if (selected == null) return const SizedBox.shrink();
        // Only this small bar rebuilds while the view moves.
        return ListenableBuilder(
          listenable: reader.repaint,
          builder: (context, _) {
            final bounds = selection.bounds();
            if (bounds == null) return const SizedBox.shrink();
            return CustomSingleChildLayout(
              delegate: _SelectionBarLayout(
                bounds,
                MediaQuery.paddingOf(context),
              ),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(24),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.copy),
                      label: Text(l10n.selectionCopy),
                      onPressed: () => _copy(context),
                    ),
                    if (DictionaryScope.maybeOf(context) case final scope?)
                      TextButton.icon(
                        icon: const Icon(Icons.menu_book_outlined),
                        label: Text(l10n.dictionaryAction),
                        onPressed: () => _lookUp(context, scope),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l10n.selectionClose,
                      onPressed: selection.clear,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Places the selection bar centred above [selection], or below it (past
/// the handles) when there is no room above, kept inside the view and clear
/// of the system bars in [padding].
class _SelectionBarLayout extends SingleChildLayoutDelegate {
  _SelectionBarLayout(this.selection, this.padding);
  final Rect selection;
  final EdgeInsets padding;

  static const _gap = 12.0;

  /// Room below the text taken by the selection handles.
  static const _handles = 24.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final top = padding.top + _gap;
    final bottom = size.height - padding.bottom - _gap - childSize.height;
    final above = selection.top - _gap - childSize.height;
    final below = selection.bottom + _handles + _gap;
    final y = above >= top ? above : below;
    final x = selection.center.dx - childSize.width / 2;
    final maxX = size.width - padding.right - _gap - childSize.width;
    return Offset(
      x.clamp(padding.left + _gap, math.max(padding.left + _gap, maxX)),
      y.clamp(top, math.max(top, bottom)),
    );
  }

  @override
  bool shouldRelayout(_SelectionBarLayout old) =>
      old.selection != selection || old.padding != padding;
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.wrong});

  final bool wrong;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_password.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.readerPasswordNeeded),
      content: TextField(
        controller: _password,
        autofocus: true,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.pdfPassword,
          errorText: widget.wrong ? l10n.pdfWrongPassword : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.unlockPdf)),
      ],
    );
  }
}
