// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'frame_probe.dart';
import 'reader_controller.dart';

/// Pointer kinds that may pan and zoom. Stylus pointers never reach the
/// pan/zoom recognizers, so the pen can write without moving the page
/// (ADR-0006, AGENTS.md §7).
const panZoomDevices = {
  PointerDeviceKind.touch,
  PointerDeviceKind.mouse,
  PointerDeviceKind.trackpad,
};

/// Continuous vertical reader (FR-VIEW-001, FR-VIEW-002, FR-VIEW-004):
/// pinch zoom, drag and fling, double-tap smart zoom and mouse-wheel
/// scrolling, painted from previews and tiles held by [controller].
class ReaderView extends StatefulWidget {
  const ReaderView({super.key, required this.controller, this.probe});

  final ReaderController controller;

  /// Records frame timings of each interaction (profile builds).
  final FrameProbe? probe;

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  Simulation? _flingX;
  Simulation? _flingY;
  Offset _flingOrigin = Offset.zero;

  double _startZoom = 1;
  Offset _focalDocument = Offset.zero;
  Offset _lastFocal = Offset.zero;
  int _pointers = 0;
  Offset? _doubleTapAt;

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
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _ticker.stop();
    widget.probe?.start();
    _startZoom = _controller.zoom;
    _focalDocument = _controller.toDocument(details.localFocalPoint);
    _lastFocal = details.localFocalPoint;
    _pointers = details.pointerCount;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
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
    // The recognizer also ends the gesture when a finger is added or lifted;
    // only the last finger lifting ends the interaction.
    if (details.pointerCount > 0) return;
    final velocity = details.velocity.pixelsPerSecond;
    if (_pointers <= 1 && velocity.distance > 50) {
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

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _ticker.stop();
      _controller.panBy(-event.scrollDelta);
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
        _controller.resize(size, ratio);
        return Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            supportedDevices: panZoomDevices,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
            onDoubleTap: () {
              _ticker.stop();
              _controller.smartZoom(_doubleTapAt ?? size.center(Offset.zero));
            },
            child: RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: ReaderPainter(
                  _controller,
                  background: colors.surfaceContainerHighest,
                  probe: widget.probe,
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
  ReaderPainter(this.controller, {required this.background, this.probe})
    : super(repaint: controller.repaint);

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
    final sheet = Paint()..color = const Color(0xFFFFFFFF);
    final image = Paint()..filterQuality = FilterQuality.low;
    var blank = false;
    for (final page in layout.pagesIn(visible.top, visible.bottom)) {
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
    canvas.restore();
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
      oldDelegate.background != background;
}
