// SPDX-License-Identifier: GPL-3.0-or-later
import 'geometry.dart';

/// Maps a cropped PDF page to view pixels with clockwise page rotation.
final class PageTransform {
  PageTransform({required PdfRect cropBox, this.rotation = 0, this.scale = 1})
    : cropBox = cropBox.normalized() {
    if (![0, 90, 180, 270].contains(rotation)) {
      throw ArgumentError.value(
        rotation,
        'rotation',
        'Expected 0, 90, 180 or 270',
      );
    }
    if (!scale.isFinite || scale <= 0) {
      throw ArgumentError.value(
        scale,
        'scale',
        'Expected a finite positive scale',
      );
    }
    if (![
      cropBox.left,
      cropBox.bottom,
      cropBox.right,
      cropBox.top,
    ].every((value) => value.isFinite)) {
      throw ArgumentError.value(cropBox, 'cropBox', 'Expected finite bounds');
    }
  }

  final PdfRect cropBox;
  final int rotation;
  final double scale;

  (double width, double height) get viewSize =>
      rotation == 90 || rotation == 270
      ? (cropBox.height * scale, cropBox.width * scale)
      : (cropBox.width * scale, cropBox.height * scale);

  (double x, double y) toView(PdfPoint point) {
    final x = point.x - cropBox.left;
    final y = point.y - cropBox.bottom;
    final (vx, vy) = switch (rotation) {
      0 => (x, cropBox.height - y),
      90 => (y, x),
      180 => (cropBox.width - x, y),
      270 => (cropBox.height - y, cropBox.width - x),
      _ => throw StateError('Invalid rotation'),
    };
    return (vx * scale, vy * scale);
  }

  PdfPoint toUser(double x, double y) {
    final vx = x / scale;
    final vy = y / scale;
    final (ux, uy) = switch (rotation) {
      0 => (vx, cropBox.height - vy),
      90 => (vy, vx),
      180 => (cropBox.width - vx, vy),
      270 => (cropBox.width - vy, cropBox.height - vx),
      _ => throw StateError('Invalid rotation'),
    };
    return PdfPoint(ux + cropBox.left, uy + cropBox.bottom);
  }
}
