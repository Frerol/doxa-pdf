// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'reader_controller.dart';

/// Paints page [page]'s preview once the controller has it.
class ThumbnailPainter extends CustomPainter {
  ThumbnailPainter(this.controller, this.page)
    : super(repaint: controller.repaint);

  final ReaderController controller;
  final int page;

  @override
  void paint(Canvas canvas, Size size) {
    final image = controller.thumbnail(page);
    if (image == null) return;
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(ThumbnailPainter old) =>
      old.controller != controller || old.page != page;
}
