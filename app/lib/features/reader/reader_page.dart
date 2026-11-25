// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:doxa_engine/doxa_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'frame_probe.dart';
import 'reader_controller.dart';
import 'reader_geometry.dart';
import 'reader_view.dart';

/// Opens a document and shows it in the continuous reader (issue #47).
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.engine,
    required this.source,
    required this.title,
    this.decoder = decodeBitmap,
  });

  final Future<PdfEngine> engine;
  final DocumentSource source;
  final String title;
  final BitmapDecoder decoder;

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (controller != null) ...[
            _ZoomMenu(controller: controller),
            IconButton(
              icon: const Icon(Icons.chrome_reader_mode_outlined),
              tooltip: l10n.viewOptions,
              onPressed: () => showViewOptions(context, controller),
            ),
          ],
        ],
      ),
      body: switch ((controller, _failure)) {
        (final ReaderController c, _) => ReaderView(
          controller: c,
          probe: _probe,
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
