// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'reader_controller.dart';
import 'reader_geometry.dart';

/// The reader's controls over the page area (UX §7 "Page indicator,
/// scrubber and history", #109): the page indicator at the top left, the
/// scrubber grip on the bottom edge (the right edge when scrolling
/// vertically) and the back/forward control at the bottom left. They are
/// children of the page area's [Stack], so they follow its size, for
/// example when the side panel docks.
List<Widget> readerChrome({
  required ReaderController controller,
  required VoidCallback onGoToPage,
}) => [
  Positioned(
    top: 8,
    left: 8,
    child: ReaderPageIndicator(controller: controller, onPressed: onGoToPage),
  ),
  // Clear of the system bars and the tablet's taskbar, which can sit over
  // the bottom of the page area.
  Positioned.fill(
    child: SafeArea(
      top: false,
      child: Stack(
        children: [
          if (controller.info.pageCount > 1)
            Positioned.fill(child: ReaderScrubber(controller: controller)),
          Positioned(
            left: 8,
            bottom: ReaderScrubber.thickness + 8,
            child: ReaderHistoryControl(controller: controller),
          ),
        ],
      ),
    ),
  ),
];

/// The page or the last page of the spread on screen.
int shownPage(ReaderController controller) {
  final layout = controller.layout;
  if (layout == null || !layout.paged) return controller.page.value;
  final pages = layout.pagesOf(controller.currentSpread);
  return pages.isEmpty ? controller.page.value : pages.last;
}

/// "iv (4 / 120)" when the page has a label, else "4 / 120".
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

/// The page on screen with its label (FR-VIEW-014); a tap opens "Go to
/// page". A plain strip at fit in paged layouts, a floating pill when
/// zoomed in or scrolling continuously.
class ReaderPageIndicator extends StatelessWidget {
  const ReaderPageIndicator({
    super.key,
    required this.controller,
    required this.onPressed,
  });

  final ReaderController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return _ViewBuilder(
      // Only this label rebuilds while the view moves.
      listenable: Listenable.merge([controller.page, controller.repaint]),
      builder: (context, _) {
        final strip = (controller.layout?.paged ?? false) && controller.atFit;
        return Material(
          color: strip
              ? scheme.surface.withValues(alpha: 0.6)
              : scheme.surfaceContainerHigh,
          elevation: strip ? 0 : 3,
          borderRadius: BorderRadius.circular(strip ? 4 : 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(strip ? 4 : 16),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                pageIndicatorText(l10n, controller, shownPage(controller)),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A grip on the bottom edge of the page area, or the right edge when
/// scrolling vertically (FR-VIEW-009). Its position maps to the page;
/// dragging it turns pages live, with a thin track shown only while
/// dragging. The first page turned by a drag is a jump the history can
/// undo (FR-VIEW-011).
class ReaderScrubber extends StatefulWidget {
  const ReaderScrubber({super.key, required this.controller});

  final ReaderController controller;

  /// The size of the grip across the edge it sits on.
  static const thickness = 40.0;

  /// The grip's length along the edge.
  static const length = 56.0;

  @override
  State<ReaderScrubber> createState() => _ReaderScrubberState();
}

class _ReaderScrubberState extends State<ReaderScrubber> {
  static const _margin = 8.0;
  bool _dragging = false;
  bool _recorded = false;

  ReaderController get _controller => widget.controller;
  bool get _vertical => _controller.layout is ContinuousLayout;

  /// The page at [global], along the edge the grip moves on.
  int _pageAt(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(global);
    final extent = _vertical ? box.size.height : box.size.width;
    final travel = extent - 2 * _margin - ReaderScrubber.length;
    final along =
        (_vertical ? local.dy : local.dx) - _margin - ReaderScrubber.length / 2;
    final t = travel <= 0 ? 0.0 : (along / travel).clamp(0.0, 1.0);
    return (t * (_controller.info.pageCount - 1)).round();
  }

  void _drag(Offset global) {
    final page = _pageAt(global);
    if (page == _controller.page.value) return;
    _controller.goToPage(page, record: !_recorded);
    _recorded = true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return _ViewBuilder(
      listenable: Listenable.merge([_controller.page, _controller.repaint]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final vertical = _vertical;
          final extent = vertical ? box.maxHeight : box.maxWidth;
          final last = _controller.info.pageCount - 1;
          final t = last <= 0 ? 0.0 : _controller.page.value / last;
          final travel = extent - 2 * _margin - ReaderScrubber.length;
          final at = _margin + t * (travel < 0 ? 0 : travel);
          const across = ReaderScrubber.thickness;
          const along = ReaderScrubber.length;
          final grip = Semantics(
            slider: true,
            label: l10n.pageScrubber,
            value: pageIndicatorText(l10n, _controller, _controller.page.value),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) => setState(() {
                _dragging = true;
                _recorded = false;
              }),
              onPanUpdate: (details) => _drag(details.globalPosition),
              onPanEnd: (_) => setState(() => _dragging = false),
              onPanCancel: () => setState(() => _dragging = false),
              child: Center(
                child: Container(
                  width: vertical ? 6 : 36,
                  height: vertical ? 36 : 6,
                  decoration: BoxDecoration(
                    color: _dragging ? scheme.primary : scheme.outline,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          );
          return Stack(
            children: [
              if (_dragging)
                vertical
                    ? Positioned(
                        top: _margin,
                        bottom: _margin,
                        right: across / 2 - 1,
                        width: 2,
                        child: ColoredBox(color: scheme.outlineVariant),
                      )
                    : Positioned(
                        left: _margin,
                        right: _margin,
                        bottom: across / 2 - 1,
                        height: 2,
                        child: ColoredBox(color: scheme.outlineVariant),
                      ),
              // Keyed, so the track appearing keeps the dragged grip.
              if (vertical)
                Positioned(
                  key: const ValueKey('grip'),
                  right: 0,
                  top: at,
                  width: across,
                  height: along,
                  child: grip,
                )
              else
                Positioned(
                  key: const ValueKey('grip'),
                  left: at,
                  bottom: 0,
                  width: along,
                  height: across,
                  child: grip,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Back and forward through jumps (FR-VIEW-011), shown after a jump. It
/// fades to a faint state when idle and comes back when used or when the
/// history changes.
class ReaderHistoryControl extends StatefulWidget {
  const ReaderHistoryControl({super.key, required this.controller});

  final ReaderController controller;

  /// How long the control stays fully visible after a change.
  static const idleAfter = Duration(seconds: 3);

  @override
  State<ReaderHistoryControl> createState() => _ReaderHistoryControlState();
}

class _ReaderHistoryControlState extends State<ReaderHistoryControl> {
  Timer? _idle;
  bool _faint = false;

  @override
  void initState() {
    super.initState();
    widget.controller.history.addListener(_wake);
    _wake();
  }

  @override
  void dispose() {
    widget.controller.history.removeListener(_wake);
    _idle?.cancel();
    super.dispose();
  }

  void _wake() {
    _idle?.cancel();
    _idle = Timer(ReaderHistoryControl.idleAfter, () {
      if (mounted) setState(() => _faint = true);
    });
    if (mounted) setState(() => _faint = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = widget.controller;
    if (!controller.canGoBack && !controller.canGoForward) {
      return const SizedBox.shrink();
    }
    return AnimatedOpacity(
      opacity: _faint ? 0.4 : 1,
      duration: const Duration(milliseconds: 300),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        elevation: 3,
        shape: const StadiumBorder(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.historyBack,
              onPressed: controller.canGoBack ? controller.goBack : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward),
              tooltip: l10n.historyForward,
              onPressed: controller.canGoForward ? controller.goForward : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A [ListenableBuilder] for the reader's notifiers, which can fire while
/// the page lays out (a resize relayouts the document): a change during a
/// build or layout rebuilds after that frame instead of during it.
class _ViewBuilder extends StatefulWidget {
  const _ViewBuilder({required this.listenable, required this.builder});

  final Listenable listenable;
  final TransitionBuilder builder;

  @override
  State<_ViewBuilder> createState() => _ViewBuilderState();
}

class _ViewBuilderState extends State<_ViewBuilder> {
  var _scheduled = false;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(_ViewBuilder old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, null);
}
