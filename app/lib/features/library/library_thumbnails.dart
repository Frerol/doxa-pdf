// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:doxa_engine/doxa_engine.dart';

import '../reader/reader_controller.dart';
import 'library_repository.dart';

/// Width of a library thumbnail in pixels.
const thumbnailWidth = 160;

/// Renders the first page of an open document into [store] at
/// [RenderPriority.thumbnail], below every request of the visible page, so
/// it never delays reading (issue #50). Does nothing if the document closes
/// first or the page cannot be rendered.
Future<void> writeThumbnail({
  required PdfEngine engine,
  required DocumentHandle document,
  required DocumentInfo info,
  required ThumbnailStore store,
  required String identity,
  BitmapDecoder decoder = decodeBitmap,
}) async {
  if (info.pageCount == 0) return;
  final page = info.pageSize(0);
  if (page.width <= 0 || page.height <= 0) return;
  final scale = (thumbnailWidth / page.width).clamp(
    0.01,
    RenderRequest.maxScale,
  );
  final width = (page.width * scale).round().clamp(1, RenderRequest.maxSide);
  final height = (page.height * scale).round().clamp(1, RenderRequest.maxSide);
  final RenderResult result;
  try {
    result = await engine.render(
      RenderRequest(
        document: document,
        pageIndex: 0,
        scale: scale,
        x: 0,
        y: 0,
        width: width,
        height: height,
        priority: RenderPriority.thumbnail,
      ),
    );
  } on PdfEngineException {
    return; // Closed while waiting.
  }
  if (result is! RenderedBitmap) return;
  final image = await decoder(result);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return;
    await store.write(identity, png.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
