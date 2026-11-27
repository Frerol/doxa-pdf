// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui' as ui;

import 'package:doxa_engine/doxa_engine.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'frame_probe.dart';
import 'reader_controller.dart';
import 'reader_geometry.dart';
import 'text_selection.dart';

/// Width of each edge tap zone, as a fraction of the view width.
const tapZoneFraction = 0.2;

/// Pointer kinds that may pan and zoom. Stylus pointers never reach the
/// pan/zoom recognizers, so the pen can write without moving the page
/// (ADR-0006, AGENTS.md §7).
const panZoomDevices = {
  PointerDeviceKind.touch,
  PointerDeviceKind.mouse,
  PointerDeviceKind.trackpad,
};

/// The reader (FR-VIEW-001..004, FR-VIEW-017..019): pinch zoom, drag and
/// fling (or, in paged layouts, swipes and edge taps that turn pages),
/// double-tap smart zoom and mouse-wheel scrolling, painted from previews
/// and tiles held by [controller].
class ReaderView extends StatefulWidget {
  const ReaderView({
    super.key,
    required this.controller,
    this.probe,
    this.onLink,
    this.selection,
    this.onTap,
    this.colorFilter,
    this.sheetColor = const Color(0xFFFFFFFF),
  });

  final ReaderController controller;

  /// Called with the target of a tapped link (FR-VIEW-010).
  final void Function(LinkTarget target)? onLink;

  /// Text selection (FR-TEXT-004); none when null.
  final TextSelectionController? selection;

  /// Called for a tap away from links, edge zones and the selection.
  final VoidCallback? onTap;

  /// Tints rendered pages (FR-VIEW-005, FR-VIEW-016); none when null.
  final ColorFilter? colorFilter;

  /// Colour of a page sheet while its images load.
  final Color sheetColor;

  /// Records frame timings of each interaction (profile builds).
  final FrameProbe? probe;

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);

  /// Page turns and settling in paged layouts.
  late final AnimationController _turn =
      AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )
        ..addListener(_onTurnTick)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            widget.probe?.stop(_controller);
          }
        });
  ViewState? _turnFrom;
  ViewState? _turnTo;
  int _startSpread = 0;
  Simulation? _flingX;
  Simulation? _flingY;
  Offset _flingOrigin = Offset.zero;

  double _startZoom = 1;
  Offset _focalDocument = Offset.zero;
  Offset _lastFocal = Offset.zero;
  int _pointers = 0;
  Offset? _doubleTapAt;

  /// The finger or mouse pointer that may become an edge tap, where it went
  /// down and when; cleared when it moves, a second pointer arrives, or it
  /// is held too long.
  int? _edgePointer;
  Offset _edgeDownAt = Offset.zero;
  Duration _edgeDownTime = Duration.zero;

  ReaderController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didHaveMemoryPressure() => _controller.trimMemory();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _turn.dispose();
    super.dispose();
  }

  /// Which selection handle a one-finger drag moves, if any.
  bool? _draggingStartHandle;

  /// The selection handle within reach of [point]: true for the start one.
  bool? _handleAt(Offset point) {
    final handles = widget.selection?.handles();
    if (handles == null) return null;
    final (start, end) = handles;
    const reach = 32.0;
    final toStart = (point - start).distance, toEnd = (point - end).distance;
    if (toStart > reach && toEnd > reach) return null;
    return toStart <= toEnd;
  }

  void _onScaleStart(ScaleStartDetails details) {
    final handle = details.pointerCount == 1
        ? _handleAt(details.localFocalPoint)
        : null;
    _draggingStartHandle = handle;
    if (handle != null) {
      widget.selection?.beginHandleDrag(start: handle);
      return;
    }
    _ticker.stop();
    _turn.stop();
    _startSpread = _controller.currentSpread;
    widget.probe?.start();
    _startZoom = _controller.zoom;
    _focalDocument = _controller.toDocument(details.localFocalPoint);
    _lastFocal = details.localFocalPoint;
    _pointers = details.pointerCount;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final handle = _draggingStartHandle;
    if (handle != null) {
      widget.selection?.moveHandle(
        start: handle,
        screenPoint: details.localFocalPoint,
      );
      return;
    }
    if (details.pointerCount != _pointers) {
      // A finger was added or lifted: restart from here without a jump.
      _pointers = details.pointerCount;
      _startZoom = _controller.zoom / details.scale;
      _focalDocument = _controller.toDocument(details.localFocalPoint);
      _lastFocal = details.localFocalPoint;
    }
    if (details.pointerCount >= 2) {
      _controller.zoomAround(
        _startZoom * details.scale,
        _focalDocument,
        details.localFocalPoint,
      );
    } else {
      _controller.panBy(details.localFocalPoint - _lastFocal);
    }
    _lastFocal = details.localFocalPoint;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_draggingStartHandle != null) {
      _draggingStartHandle = null;
      return;
    }
    // The recognizer also ends the gesture when a finger is added or lifted;
    // only the last finger lifting ends the interaction.
    if (details.pointerCount > 0) return;
    final velocity = details.velocity.pixelsPerSecond;
    if (_controller.layout?.paged ?? false) {
      final target = _controller.settle(
        startSpread: _startSpread,
        velocity: _pointers <= 1 ? velocity : Offset.zero,
      );
      if (target != null) {
        _animateTo(target); // The probe stops when the animation ends.
      } else {
        widget.probe?.stop(_controller);
      }
    } else if (_pointers <= 1 && velocity.distance > 50) {
      _flingOrigin = Offset.zero;
      _flingX = ClampingScrollSimulation(position: 0, velocity: velocity.dx);
      _flingY = ClampingScrollSimulation(position: 0, velocity: velocity.dy);
      _ticker.start();
    } else {
      widget.probe?.stop(_controller);
    }
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final position = Offset(_flingX!.x(t), _flingY!.x(t));
    _controller.panBy(position - _flingOrigin);
    _flingOrigin = position;
    if (_flingX!.isDone(t) && _flingY!.isDone(t)) {
      _ticker.stop();
      widget.probe?.stop(_controller);
    }
  }

  void _animateTo(ViewState target) {
    _ticker.stop();
    _turnFrom = (
      zoom: _controller.zoom,
      offset: _controller.offset,
      atFit: _controller.atFit,
    );
    _turnTo = target;
    _turn.forward(from: 0);
  }

  void _onTurnTick() {
    final from = _turnFrom, to = _turnTo;
    if (from == null || to == null) return;
    final t = Curves.easeOutCubic.transform(_turn.value);
    _controller.setView((
      zoom: from.zoom + (to.zoom - from.zoom) * t,
      offset: Offset.lerp(from.offset, to.offset, t)!,
      atFit: _turn.value == 1 ? to.atFit : from.atFit,
    ));
  }

  /// Which edge tap zone [position] is in, in paged layouts with tap zones
  /// on (FR-VIEW-017): true for the left edge, false for the right, null
  /// elsewhere.
  bool? _edgeAt(Offset position, Size size) {
    if (!_controller.options.tapZones ||
        !(_controller.layout?.paged ?? false)) {
      return null;
    }
    final zone = size.width * tapZoneFraction;
    if (position.dx < zone) return true;
    if (position.dx > size.width - zone) return false;
    return null;
  }

  /// Turns one page towards the left or right edge. A tap during a turn
  /// animation continues from where that turn was going, so quick taps
  /// each turn one page.
  void _turnTowards({required bool left}) {
    final pending = _turn.isAnimating ? _turnTo : null;
    _turn.stop();
    if (pending != null) _controller.setView(pending);
    final target = _controller.turn(towardsLeft: left);
    if (target != null) _animateTo(target);
  }

  // Edge taps turn the page as soon as the finger lifts (FR-VIEW-017).
  // Going through the tap recognizer would wait for the double-tap timeout,
  // which edge taps never need: two quick edge taps simply turn two pages,
  // one per tap, and never zoom.
  void _onEdgePointerDown(PointerDownEvent event, Size size) {
    if (_edgePointer != null || !panZoomDevices.contains(event.kind)) {
      _edgePointer = null;
      return;
    }
    if (_edgeAt(event.localPosition, size) == null) return;
    _edgePointer = event.pointer;
    _edgeDownAt = event.localPosition;
    _edgeDownTime = event.timeStamp;
  }

  void _onEdgePointerMove(PointerMoveEvent event) {
    if (event.pointer == _edgePointer &&
        (event.localPosition - _edgeDownAt).distance > kTouchSlop) {
      _edgePointer = null;
    }
  }

  void _onEdgePointerUp(PointerUpEvent event, Size size) {
    if (event.pointer != _edgePointer) return;
    _edgePointer = null;
    if (event.timeStamp - _edgeDownTime > kLongPressTimeout) return;
    // A tap with text selected only clears the selection (see _onTapUp).
    if (widget.selection?.hasSelection ?? false) return;
    final left = _edgeAt(event.localPosition, size);
    if (left != null) {
      _ticker.stop();
      _turnTowards(left: left);
    }
  }

  Future<void> _onTapUp(TapUpDetails details, Size size) async {
    // A tap outside the text first clears the selection.
    final selection = widget.selection;
    if (selection != null && selection.hasSelection) {
      selection.clear();
      return;
    }
    // Edge taps already turned the page on pointer up.
    if (_edgeAt(details.localPosition, size) != null) return;
    final onLink = widget.onLink;
    final target = onLink == null
        ? null
        : await _controller.linkAt(details.localPosition);
    if (!mounted) return;
    if (target != null) {
      onLink!(target);
    } else {
      widget.onTap?.call();
    }
  }

  void _onDoubleTap(Size size) {
    final at = _doubleTapAt ?? size.center(Offset.zero);
    // On an edge each tap already turned a page on pointer up (recognizers
    // run after the Listener), so leave that turn animating; edge taps never
    // zoom.
    if (_edgeAt(at, size) != null) return;
    _ticker.stop();
    _turn.stop();
    _controller.smartZoom(at);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _ticker.stop();
    final layout = _controller.layout;
    final delta = event.scrollDelta;
    if (layout != null &&
        layout.paged &&
        (_controller.atFit || _controller.zoom <= 1.05)) {
      // One page per wheel step; steps during the turn animation are ignored.
      final step = delta.dy.abs() >= delta.dx.abs() ? delta.dy : delta.dx;
      if (step == 0 || _turn.isAnimating) return;
      final target = _controller.turnPage(forward: step > 0);
      if (target != null) _animateTo(target);
      return;
    }
    _turn.stop();
    if (layout is StripLayout && delta.dx == 0) {
      // A vertical wheel scrolls a horizontal strip sideways.
      _controller.panBy(Offset(-delta.dy, 0));
    } else {
      _controller.panBy(-delta);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final ratio = MediaQuery.devicePixelRatioOf(context);
        // Layout only changes numbers in the controller; it never rebuilds.
        if (_turn.isAnimating &&
            (size != _controller.viewSize ||
                ratio != _controller.devicePixelRatio)) {
          _turn.stop();
        }
        _controller.resize(size, ratio);
        return Listener(
          onPointerSignal: _onPointerSignal,
          onPointerDown: (event) => _onEdgePointerDown(event, size),
          onPointerMove: _onEdgePointerMove,
          onPointerUp: (event) => _onEdgePointerUp(event, size),
          onPointerCancel: (_) => _edgePointer = null,
          child: GestureDetector(
            supportedDevices: panZoomDevices,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            onTapUp: (details) => _onTapUp(details, size),
            onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
            onDoubleTap: () => _onDoubleTap(size),
            onLongPressStart: widget.selection == null
                ? null
                : (details) {
                    _ticker.stop();
                    _turn.stop();
                    unawaited(
                      widget.selection!.selectWordAt(details.localPosition),
                    );
                  },
            onLongPressMoveUpdate: widget.selection == null
                ? null
                : (details) => unawaited(
                    widget.selection!.extendTo(details.localPosition),
                  ),
            child: RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: ReaderPainter(
                  _controller,
                  // Behind the page (UX §5): the deepest surface in the dark theme,
                  // a soft grey in the light one.
                  background: Theme.of(context).brightness == Brightness.dark
                      ? colors.surfaceContainerLowest
                      : colors.surfaceContainerHigh,
                  probe: widget.probe,
                  selection: widget.selection,
                  highlightColors: {
                    HighlightLayer.searchHits: const Color(0x66FFD54F),
                    HighlightLayer.currentHit: const Color(0x99FF9800),
                    HighlightLayer.selection: colors.primary.withValues(
                      alpha: 0.3,
                    ),
                  },
                  handleColor: colors.primary,
                  colorFilter: widget.colorFilter,
                  sheetColor: widget.sheetColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the visible pages: a white sheet, the preview, then the tiles of
/// the current zoom bucket on top.
class ReaderPainter extends CustomPainter {
  ReaderPainter(
    this.controller, {
    required this.background,
    this.probe,
    this.selection,
    this.highlightColors = const {},
    this.handleColor = const Color(0xFF3F51B5),
    this.colorFilter,
    this.sheetColor = const Color(0xFFFFFFFF),
  }) : super(repaint: controller.repaint);

  final ColorFilter? colorFilter;
  final Color sheetColor;

  final TextSelectionController? selection;
  final Map<HighlightLayer, Color> highlightColors;
  final Color handleColor;

  final ReaderController controller;
  final Color background;
  final FrameProbe? probe;

  @override
  void paint(Canvas canvas, Size size) {
    // Clip to our bounds: an unclipped fill would cover the whole screen.
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final layout = controller.layout;
    if (layout == null) return;
    final visible = controller.visibleRect;
    final offset = controller.offset;
    canvas
      ..save()
      ..scale(controller.zoom)
      ..translate(-offset.dx, -offset.dy);
    final sheet = Paint()..color = sheetColor;
    final image = Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = colorFilter;
    var blank = false;
    for (final page in layout.pagesIn(visible)) {
      final rect = layout.pageRect(page);
      canvas.drawRect(rect, sheet);
      final preview = controller.cache.peek('p:$page');
      if (preview == null) {
        blank = true;
      } else {
        _draw(canvas, preview, rect, image);
      }
      for (final tile in controller.visibleTiles(page)) {
        final tileImage = controller.cache.peek(tile.key);
        if (tileImage != null) {
          _draw(canvas, tileImage, tile.destination, image);
        }
      }
    }
    for (final page in layout.pagesIn(visible)) {
      for (final MapEntry(key: layer, value: color)
          in highlightColors.entries) {
        final paint = Paint()..color = color;
        for (final rect in controller.highlights(layer, page)) {
          final target = controller.documentRect(page, rect);
          if (target != null) canvas.drawRect(target, paint);
        }
      }
    }
    canvas.restore();
    final handles = selection?.handles();
    if (handles != null) {
      final paint = Paint()..color = handleColor;
      for (final point in [handles.$1, handles.$2]) {
        canvas
          ..drawCircle(point + const Offset(0, 8), 8, paint)
          ..drawRect(Rect.fromLTWH(point.dx - 1, point.dy - 16, 2, 16), paint);
      }
    }
    probe?.painted(blank: blank);
  }

  void _draw(Canvas canvas, ui.Image image, Rect destination, Paint paint) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destination,
      paint,
    );
  }

  @override
  bool shouldRepaint(ReaderPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.background != background ||
      oldDelegate.selection != selection ||
      oldDelegate.handleColor != handleColor ||
      oldDelegate.colorFilter != colorFilter ||
      oldDelegate.sheetColor != sheetColor ||
      !mapEquals(oldDelegate.highlightColors, highlightColors);
}
