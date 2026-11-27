// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

import 'package:doxa_core/doxa_core.dart';

/// Where a document comes from.
sealed class DocumentSource {
  const DocumentSource();
}

/// A document read from a file path.
///
/// On Android, a content URI opened by the platform layer can be passed as
/// `/proc/self/fd/<fd>` while its file descriptor stays open.
final class FileSource extends DocumentSource {
  const FileSource(this.path);
  final String path;
}

/// A document held in memory. The engine keeps its own copy.
final class MemorySource extends DocumentSource {
  const MemorySource(this.bytes);
  final Uint8List bytes;
}

/// Identifies a document opened by a `PdfEngine`.
final class DocumentHandle {
  const DocumentHandle(this.id);
  final int id;

  @override
  bool operator ==(Object other) => other is DocumentHandle && id == other.id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => 'DocumentHandle($id)';
}

/// Result of `PdfEngine.open`.
sealed class OpenResult {
  const OpenResult();
}

final class DocumentOpened extends OpenResult {
  const DocumentOpened(this.handle, this.info);
  final DocumentHandle handle;
  final DocumentInfo info;
}

/// The document is encrypted and no password was given (FR-FILE-003).
final class PasswordRequired extends OpenResult {
  const PasswordRequired();
}

/// The given password does not open the document (FR-FILE-003).
final class WrongPassword extends OpenResult {
  const WrongPassword();
}

final class OpenFailed extends OpenResult {
  const OpenFailed(this.reason, [this.detail = '']);
  final OpenFailure reason;
  final String detail;
}

/// What a save did (FR-SAVE-002). A failed save never changed the target.
sealed class SaveResult {
  const SaveResult();
}

final class Saved extends SaveResult {
  const Saved(this.bytes);

  /// The size of the saved file.
  final int bytes;
}

final class SaveFailed extends SaveResult {
  const SaveFailed(this.reason, [this.detail = '']);
  final SaveFailure reason;
  final String detail;
}

enum SaveFailure {
  /// The disk is full.
  noSpace,

  /// The temp file could not be written.
  writeFailed,

  /// The written file did not reopen as a good copy of the document.
  verifyFailed,

  /// The written file could not replace the target.
  cannotReplace,
}

enum OpenFailure {
  /// The file is missing or cannot be read.
  file,

  /// The data is not a PDF, or it is too damaged to open.
  format,

  /// The document uses an unsupported security handler.
  security,

  unknown,
}

/// What `PdfEngine.open` reports about a document. Page sizes are cheap to
/// read for every page; everything that needs a loaded page is in
/// [PageDetails].
final class DocumentInfo {
  DocumentInfo({
    required Float64List pageSizes,
    required this.pageLabels,
    required this.metadata,
  }) : _pageSizes = pageSizes {
    if (pageSizes.length.isOdd || pageLabels.length != pageCount) {
      throw ArgumentError('Page sizes and labels do not match');
    }
  }

  final Float64List _pageSizes;

  /// The label of each page (FR-VIEW-014), or null where the document has
  /// none. Use the 1-based page number then.
  final List<String?> pageLabels;
  final DocumentMetadata metadata;

  int get pageCount => _pageSizes.length ~/ 2;

  /// Displayed page size in points: the effective crop box, already rotated.
  ({double width, double height}) pageSize(int index) {
    RangeError.checkValidIndex(index, pageLabels, 'index', pageCount);
    return (width: _pageSizes[index * 2], height: _pageSizes[index * 2 + 1]);
  }

  bool get hasPageLabels => pageLabels.any((label) => label != null);
}

/// The document information dictionary. Dates are raw PDF date strings
/// (parse them with `PdfDate`).
final class DocumentMetadata {
  const DocumentMetadata({
    this.title,
    this.author,
    this.subject,
    this.keywords,
    this.creator,
    this.producer,
    this.creationDate,
    this.modificationDate,
  });

  final String? title;
  final String? author;
  final String? subject;
  final String? keywords;
  final String? creator;
  final String? producer;
  final String? creationDate;
  final String? modificationDate;
}

/// Geometry of one page, for mapping PDF user space to the view with
/// `PageTransform(cropBox: cropBox, rotation: rotation)`.
final class PageDetails {
  const PageDetails({
    required this.pageIndex,
    required this.cropBox,
    required this.rotation,
  });

  final int pageIndex;

  /// Effective crop box in PDF user space (crop box clipped to the media box).
  final PdfRect cropBox;

  /// Clockwise rotation in degrees: 0, 90, 180 or 270.
  final int rotation;

  PageTransform transform({double scale = 1}) =>
      PageTransform(cropBox: cropBox, rotation: rotation, scale: scale);
}

/// A position in the document. [x], [y] and [zoom] are null when the
/// destination leaves them unchanged. Coordinates are PDF user space.
final class PdfDestination {
  const PdfDestination(this.pageIndex, {this.x, this.y, this.zoom});
  final int pageIndex;
  final double? x;
  final double? y;
  final double? zoom;

  @override
  bool operator ==(Object other) =>
      other is PdfDestination &&
      pageIndex == other.pageIndex &&
      x == other.x &&
      y == other.y &&
      zoom == other.zoom;
  @override
  int get hashCode => Object.hash(pageIndex, x, y, zoom);
  @override
  String toString() => 'PdfDestination($pageIndex, x: $x, y: $y, zoom: $zoom)';
}

/// An outline (table of contents) entry (FR-VIEW-007).
final class OutlineNode {
  const OutlineNode({
    required this.title,
    this.target,
    this.children = const [],
  });

  final String title;

  /// Where the entry leads, or null when it has no usable target.
  final LinkTarget? target;
  final List<OutlineNode> children;
}

/// What a link or outline entry points to (FR-VIEW-010).
sealed class LinkTarget {
  const LinkTarget();
}

final class GoToTarget extends LinkTarget {
  const GoToTarget(this.destination);
  final PdfDestination destination;
}

final class UriTarget extends LinkTarget {
  const UriTarget(this.uri);
  final String uri;
}

/// A target the reader cannot follow (another file, a launch action, ...).
final class UnsupportedTarget extends LinkTarget {
  const UnsupportedTarget(this.actionType);

  /// PDFium's `PDFACTION_*` value.
  final int actionType;
}

/// A link annotation on a page.
final class PageLink {
  const PageLink(this.rect, this.target);

  /// Active area in PDF user space.
  final PdfRect rect;
  final LinkTarget target;
}

/// The text layer of a page (chars and boxes) for selection and search.
final class PageText {
  PageText({
    required this.pageIndex,
    required this.text,
    required this.charIndexOfUnit,
    required this.charBoxes,
  }) {
    if (charIndexOfUnit.length != text.length || charBoxes.length.isOdd) {
      throw ArgumentError('Text layer arrays do not match');
    }
  }

  final int pageIndex;

  /// The page text in PDFium's order. PDFium adds spaces and line breaks
  /// between words and lines; those have empty boxes.
  final String text;

  /// The PDFium char index of each UTF-16 code unit of [text].
  final Int32List charIndexOfUnit;

  /// Four values per PDFium char (left, bottom, right, top) in PDF user
  /// space. A char without a box has all four values equal to zero.
  final Float64List charBoxes;

  int get charCount => charBoxes.length ~/ 4;

  /// The box of char [index], or null if it has none.
  PdfRect? charBox(int index) {
    RangeError.checkValidIndex(index, null, 'index', charCount);
    final l = charBoxes[index * 4], b = charBoxes[index * 4 + 1];
    final r = charBoxes[index * 4 + 2], t = charBoxes[index * 4 + 3];
    if (l == 0 && b == 0 && r == 0 && t == 0) return null;
    return PdfRect(l, b, r, t);
  }
}

/// A full-text search (FR-TEXT-001, FR-TEXT-002).
final class SearchQuery {
  const SearchQuery(
    this.text, {
    this.matchCase = false,
    this.wholeWord = false,
    this.ignoreDiacritics = true,
  });

  final String text;
  final bool matchCase;
  final bool wholeWord;

  /// "acao" finds "ação". On by default (FR-TEXT-002).
  final bool ignoreDiacritics;
}

/// One search match. [rects] has one rectangle per line in PDF user space.
final class SearchHit {
  const SearchHit({
    required this.pageIndex,
    required this.charIndex,
    required this.charCount,
    required this.rects,
  });

  final int pageIndex;

  /// First PDFium char of the match and the number of chars it spans.
  final int charIndex;
  final int charCount;
  final List<PdfRect> rects;
}

/// Engine scheduling order, most urgent first (ADR-0005). Requests with the
/// same priority run oldest first, except renders, where a newer viewport
/// generation wins.
enum RenderPriority {
  visiblePreview,
  visibleTile,
  nearPreview,
  nearTile,
  thumbnail,
  background;

  /// Previews and thumbnails stay useful after the viewport moves, so a new
  /// generation does not drop them.
  bool get keptWhenStale => this == visiblePreview || this == thumbnail;
}

/// A rectangle of a page rendered at [scale] pixels per point.
///
/// [x], [y], [width] and [height] are pixels in the displayed (rotated,
/// cropped) page at that scale, with the origin at the top left, so a
/// 512 px tile at column c and row r is `x: c * 512, y: r * 512`.
final class RenderRequest {
  RenderRequest({
    required this.document,
    required this.pageIndex,
    required this.scale,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.priority = RenderPriority.visibleTile,
    this.generation = 0,
  }) {
    if (!scale.isFinite || scale <= 0 || scale > maxScale) {
      throw ArgumentError.value(scale, 'scale', 'Expected 0 < scale <= 64');
    }
    if (width <= 0 || height <= 0 || width > maxSide || height > maxSide) {
      throw ArgumentError('Expected 1..$maxSide px, got $width x $height');
    }
  }

  static const maxScale = 64.0;
  static const maxSide = 4096;

  final DocumentHandle document;
  final int pageIndex;
  final double scale;
  final int x;
  final int y;
  final int width;
  final int height;
  final RenderPriority priority;

  /// Viewport generation (see `PdfEngine.setGeneration`).
  final int generation;
}

sealed class RenderResult {
  const RenderResult();
}

/// Tightly packed RGBA pixels (4 bytes per pixel, not premultiplied),
/// ready for `ui.decodeImageFromPixels` with `PixelFormat.rgba8888`.
final class RenderedBitmap extends RenderResult {
  const RenderedBitmap(this.width, this.height, this.pixels);
  final int width;
  final int height;
  final Uint8List pixels;
}

/// The request was dropped before PDFium rendered it.
final class RenderSkipped extends RenderResult {
  const RenderSkipped(this.reason);
  final SkipReason reason;
}

enum SkipReason {
  /// A newer viewport generation replaced it.
  stale,

  /// Its `CancelToken` was cancelled.
  cancelled,

  /// Its document was closed.
  closed,
}

/// Cancels a pending engine request.
final class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  /// Runs [listener] once on [cancel], right away if already cancelled.
  /// Returns a function that removes the listener again.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// Thrown by engine calls that fail for a reason other than the document
/// itself (bad page index, closed handle, engine stopped).
final class PdfEngineException implements Exception {
  const PdfEngineException(this.kind, this.message);
  final EngineErrorKind kind;
  final String message;

  @override
  String toString() => 'PdfEngineException(${kind.name}): $message';
}

enum EngineErrorKind {
  /// The document handle is unknown or already closed.
  unknownDocument,

  /// A page index is out of range.
  invalidPage,

  /// PDFium failed on this document (for example, a damaged page).
  documentError,

  /// The engine isolate has stopped.
  stopped,

  /// No annotation of the page has the given id.
  unknownAnnotation,

  /// The edit cannot be made without losing what another app wrote, or
  /// the annotation is not one Doxa can create (FR-ANNO-002).
  unsupportedEdit,

  internal,
}
