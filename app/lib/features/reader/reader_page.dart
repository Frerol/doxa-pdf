// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'frame_probe.dart';
import 'navigation_panel.dart';
import 'reader_controller.dart';
import 'reader_geometry.dart';
import 'reader_view.dart';

/// Opens external links in another app; injectable for tests.
typedef UriOpener = Future<bool> Function(String uri);

Future<bool> _openWithPlatform(String uri) => DoxaPlatform().openUri(uri);

/// Opens a document and shows it in the reader (issues #47, #48, #52).
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.engine,
    required this.source,
    required this.title,
    this.decoder = decodeBitmap,
    this.openUri = _openWithPlatform,
  });

  final Future<PdfEngine> engine;
  final DocumentSource source;
  final String title;
  final BitmapDecoder decoder;
  final UriOpener openUri;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

enum _Failure { password, open }

class _ReaderPageState extends State<ReaderPage> {
  PdfEngine? _engine;
  ReaderController? _controller;
  _Failure? _failure;
  final FrameProbe? _probe = kReleaseMode ? null : FrameProbe();

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    OpenResult result;
    PdfEngine engine;
    try {
      engine = await widget.engine;
      result = await engine.open(widget.source);
    } on Object catch (error) {
      debugPrint('Doxa: cannot open ${widget.title}: $error');
      if (mounted) setState(() => _failure = _Failure.open);
      return;
    }
    if (!mounted) {
      if (result is DocumentOpened) unawaited(engine.close(result.handle));
      return;
    }
    setState(() {
      _engine = engine;
      switch (result) {
        case DocumentOpened(:final handle, :final info):
          _controller = ReaderController(
            engine: engine,
            document: handle,
            info: info,
            decoder: widget.decoder,
          );
        case PasswordRequired() || WrongPassword():
          _failure = _Failure.password;
        case OpenFailed():
          _failure = _Failure.open;
      }
    });
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.dispose();
      unawaited(_engine?.close(controller.document));
    }
    _probe?.dispose();
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
    final controller = _controller;
    final body = Scaffold(
      drawer: controller == null || controller.info.pageCount == 0
          ? null
          : NavigationPanel(
              controller: controller,
              onFollow: (target) {
                Navigator.of(context).pop();
                unawaited(_follow(target));
              },
            ),
      appBar: AppBar(
        // The contents button opens the drawer; no extra menu button.
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop() ? const BackButton() : null,
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
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
            _ZoomMenu(controller: controller),
            IconButton(
              icon: const Icon(Icons.chrome_reader_mode_outlined),
              tooltip: l10n.viewOptions,
              onPressed: () => showViewOptions(context, controller),
            ),
          ],
        ],
      ),
      bottomNavigationBar: controller == null || controller.info.pageCount < 2
          ? null
          : _PageScrubber(controller: controller),
      body: switch ((controller, _failure)) {
        (final ReaderController c, _) => ReaderView(
          controller: c,
          probe: _probe,
          onLink: _follow,
        ),
        (_, _Failure.password) => _Message(l10n.readerPasswordNeeded),
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
    // The system back gesture first walks back through link jumps
    // (FR-VIEW-011), then leaves the document.
    return ValueListenableBuilder(
      valueListenable: controller.history,
      builder: (context, _, child) => PopScope(
        canPop: !controller.canGoBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.goBack();
        },
        child: child!,
      ),
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
  ReaderController controller,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => _ViewOptions(controller: controller),
);

class _ViewOptions extends StatefulWidget {
  const _ViewOptions({required this.controller});
  final ReaderController controller;

  @override
  State<_ViewOptions> createState() => _ViewOptionsState();
}

class _ViewOptionsState extends State<_ViewOptions> {
  ReaderOptions get _options => widget.controller.options;

  void _set(ReaderOptions options) =>
      setState(() => widget.controller.setOptions(options));

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
                  : (value) => _set(_options.copyWith(rightToLeft: value)),
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
