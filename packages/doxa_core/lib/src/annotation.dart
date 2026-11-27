// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:math' as math;

import 'annotation_id.dart';
import 'geometry.dart';

/// How Doxa marks the annotations it owns (ADR-0005 §5): an `/NM` made of
/// [idPrefix] and a UUID v4, plus the private key [versionKey]. Both must
/// be present. An `/NM` with the prefix alone, which another app could
/// copy, does not make an annotation Doxa's.
abstract final class DoxaMarker {
  /// The start of the `/NM` of every annotation Doxa creates.
  static const idPrefix = 'doxa:';

  /// The private key Doxa writes into every annotation it creates. Its
  /// value is [version], a text string.
  static const versionKey = 'DoxaVersion';

  /// The version of what Doxa writes, raised when that changes (for
  /// example the `/DoxaPressure` encoding).
  static const version = '1';

  /// A new `/NM` for an annotation Doxa creates.
  static String newId() => '$idPrefix${AnnotationId.generate()}';

  /// Whether [nm] is shaped like an id that Doxa creates.
  static bool isDoxaId(String? nm) =>
      nm != null &&
      nm.startsWith(idPrefix) &&
      AnnotationId.isValid(nm.substring(idPrefix.length));

  /// Whether an annotation with this `/NM` and [versionKey] value is
  /// Doxa's own.
  static bool owns({required String? nm, required String? versionValue}) =>
      isDoxaId(nm) && versionValue != null && versionValue.isNotEmpty;
}

/// The text markup subtypes Doxa creates and edits (FR-MARK-001).
enum MarkupKind {
  highlight('Highlight'),
  underline('Underline'),
  squiggly('Squiggly'),
  strikeOut('StrikeOut');

  const MarkupKind(this.subtype);

  /// The PDF `/Subtype` name, without the slash.
  final String subtype;

  /// The kind for a PDF `/Subtype` name, or null for any other subtype.
  static MarkupKind? fromSubtype(String subtype) {
    for (final kind in values) {
      if (kind.subtype == subtype) return kind;
    }
    return null;
  }
}

/// Which ink tool drew an Ink annotation: the pen, or the highlighter pen
/// (semi-transparent, flat tip, Multiply; FR-INK-004).
enum InkTool { pen, highlighter }

/// One annotation of a page, in PDF user space (y grows upwards).
///
/// Only the keys Doxa reads or changes are modelled. Every other key of an
/// annotation, including the unknown keys and the appearance streams of
/// annotations made by other apps, stays in the PDF: the engine patches the
/// keys it changes and never rebuilds an annotation from this model
/// (FR-ANNO-002, `docs/plan/03-architecture.md` §5).
sealed class Annotation {
  const Annotation({
    required this.id,
    required this.pageIndex,
    required this.rect,
    this.color,
    this.opacity = 1,
    this.author,
    this.contents,
    this.modified,
    this.flags = printFlag,
    this.byDoxa = false,
  });

  /// The PDF `/F` bit that makes an annotation print (bit 3).
  static const printFlag = 4;

  /// The PDF `/F` bit that hides an annotation (bit 2).
  static const hiddenFlag = 2;

  /// `/NM`. A foreign annotation without one gets an id in memory only,
  /// written to the file only when that annotation is edited.
  final String id;
  final int pageIndex;

  /// `/Rect`.
  final PdfRect rect;

  /// `/C` as 0xRRGGBB, or null where the annotation has no colour.
  final int? color;

  /// `/CA`, from 0 to 1.
  final double opacity;

  /// `/T`.
  final String? author;

  /// `/Contents`.
  final String? contents;

  /// `/M`.
  final DateTime? modified;

  /// `/F`.
  final int flags;

  /// Whether Doxa created it ([DoxaMarker]). Doxa draws its own
  /// annotations itself and hides them in the render instance (ADR-0005).
  final bool byDoxa;

  /// The `/Subtype` name, without the slash.
  String get subtype;

  bool get isHidden => flags & hiddenFlag != 0;

  bool _sameBase(Annotation other) =>
      id == other.id &&
      pageIndex == other.pageIndex &&
      rect == other.rect &&
      color == other.color &&
      opacity == other.opacity &&
      author == other.author &&
      contents == other.contents &&
      modified == other.modified &&
      flags == other.flags &&
      byDoxa == other.byDoxa;

  int get _baseHash => Object.hash(
    id,
    pageIndex,
    rect,
    color,
    opacity,
    author,
    contents,
    modified,
    flags,
    byDoxa,
  );
}

/// A highlight, underline, squiggly or strikeout (FR-MARK-001).
final class TextMarkup extends Annotation {
  /// A markup whose `/Rect` is the bounding box of [quads].
  TextMarkup({
    required super.id,
    required super.pageIndex,
    required this.kind,
    required this.quads,
    this.text,
    super.color,
    super.opacity,
    super.author,
    super.contents,
    super.modified,
    super.flags,
    super.byDoxa,
    PdfRect? rect,
  }) : assert(quads.isNotEmpty, 'A markup covers at least one quad'),
       super(rect: rect ?? boundsOfQuads(quads));

  final MarkupKind kind;

  /// `/QuadPoints`, one quad per line fragment.
  final List<PdfQuad> quads;

  /// The text the markup covers, for review and export (FR-MARK-010).
  /// Doxa writes it to `/Contents` when the user has not written a note.
  final String? text;

  @override
  String get subtype => kind.subtype;

  /// The bounding box of [quads], which may be rotated.
  static PdfRect boundsOfQuads(List<PdfQuad> quads) =>
      quads.map((q) => q.boundingRect).reduce((a, b) => a.union(b));

  TextMarkup copyWith({
    MarkupKind? kind,
    List<PdfQuad>? quads,
    String? text,
    int? color,
    double? opacity,
    String? author,
    String? contents,
    DateTime? modified,
    int? flags,
  }) => TextMarkup(
    id: id,
    pageIndex: pageIndex,
    kind: kind ?? this.kind,
    quads: quads ?? this.quads,
    // New quads mean a new /Rect; otherwise the current one is kept.
    rect: quads == null ? rect : null,
    text: text ?? this.text,
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
    author: author ?? this.author,
    contents: contents ?? this.contents,
    modified: modified ?? this.modified,
    flags: flags ?? this.flags,
    byDoxa: byDoxa,
  );

  @override
  bool operator ==(Object other) =>
      other is TextMarkup &&
      _sameBase(other) &&
      kind == other.kind &&
      text == other.text &&
      _listEquals(quads, other.quads);

  @override
  int get hashCode => Object.hash(_baseHash, kind, text, Object.hashAll(quads));
}

/// One stroke of an Ink annotation: its centreline and, when the stylus
/// reported it, the pressure at each point.
final class InkStroke {
  InkStroke(this.points, {this.pressures})
    : assert(points.isNotEmpty, 'A stroke has at least one point'),
      assert(
        pressures == null || pressures.length == points.length,
        'One pressure per point',
      );

  /// The centreline, as written to `/InkList`.
  final List<PdfPoint> points;

  /// From 0 to 1, one per point; null without pressure.
  final List<double>? pressures;

  @override
  bool operator ==(Object other) =>
      other is InkStroke &&
      _listEquals(points, other.points) &&
      _nullableListEquals(pressures, other.pressures);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(points),
    pressures == null ? null : Object.hashAll(pressures!),
  );
}

/// Freehand ink (FR-INK-001).
final class InkAnnotation extends Annotation {
  /// An ink annotation whose `/Rect` covers [strokes] and their width.
  InkAnnotation({
    required super.id,
    required super.pageIndex,
    required this.strokes,
    required this.width,
    this.tool = InkTool.pen,
    super.color,
    super.opacity,
    super.author,
    super.contents,
    super.modified,
    super.flags,
    super.byDoxa,
    PdfRect? rect,
  }) : assert(strokes.isNotEmpty, 'Ink has at least one stroke'),
       assert(width > 0, 'Ink has a positive width'),
       super(rect: rect ?? boundsOfStrokes(strokes, width));

  final List<InkStroke> strokes;

  /// `/BS /W`: the width at full pressure, in points.
  final double width;
  final InkTool tool;

  @override
  String get subtype => 'Ink';

  /// The box around every point, grown by half of [width] so that the
  /// outline fits.
  static PdfRect boundsOfStrokes(List<InkStroke> strokes, double width) {
    var left = double.infinity, bottom = double.infinity;
    var right = double.negativeInfinity, top = double.negativeInfinity;
    for (final stroke in strokes) {
      for (final p in stroke.points) {
        left = math.min(left, p.x);
        bottom = math.min(bottom, p.y);
        right = math.max(right, p.x);
        top = math.max(top, p.y);
      }
    }
    return PdfRect(left, bottom, right, top).inflate(width / 2);
  }

  InkAnnotation copyWith({
    List<InkStroke>? strokes,
    double? width,
    InkTool? tool,
    int? color,
    double? opacity,
    String? author,
    String? contents,
    DateTime? modified,
    int? flags,
  }) => InkAnnotation(
    id: id,
    pageIndex: pageIndex,
    strokes: strokes ?? this.strokes,
    width: width ?? this.width,
    // New geometry means a new /Rect; otherwise the current one is kept.
    rect: strokes == null && width == null ? rect : null,
    tool: tool ?? this.tool,
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
    author: author ?? this.author,
    contents: contents ?? this.contents,
    modified: modified ?? this.modified,
    flags: flags ?? this.flags,
    byDoxa: byDoxa,
  );

  @override
  bool operator ==(Object other) =>
      other is InkAnnotation &&
      _sameBase(other) &&
      width == other.width &&
      tool == other.tool &&
      _listEquals(strokes, other.strokes);

  @override
  int get hashCode =>
      Object.hash(_baseHash, width, tool, Object.hashAll(strokes));
}

/// Any other annotation (notes, links, shapes, stamps, form widgets…),
/// kept so it can be listed and its colour or contents edited. Doxa never
/// rebuilds it.
final class OtherAnnotation extends Annotation {
  const OtherAnnotation({
    required super.id,
    required super.pageIndex,
    required super.rect,
    required this.subtype,
    super.color,
    super.opacity,
    super.author,
    super.contents,
    super.modified,
    super.flags,
    super.byDoxa,
  });

  @override
  final String subtype;

  OtherAnnotation copyWith({
    int? color,
    double? opacity,
    String? author,
    String? contents,
    DateTime? modified,
    int? flags,
  }) => OtherAnnotation(
    id: id,
    pageIndex: pageIndex,
    rect: rect,
    subtype: subtype,
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
    author: author ?? this.author,
    contents: contents ?? this.contents,
    modified: modified ?? this.modified,
    flags: flags ?? this.flags,
    byDoxa: byDoxa,
  );

  @override
  bool operator ==(Object other) =>
      other is OtherAnnotation && _sameBase(other) && subtype == other.subtype;

  @override
  int get hashCode => Object.hash(_baseHash, subtype);
}

/// The `/DoxaPressure` text of an Ink annotation: each pressure quantised
/// to one of [levels] steps and written as one character of the base64url
/// alphabet, with a comma between strokes. A text string is used because
/// PDFium writes no arrays into annotation dictionaries
/// (`docs/plan/04-pdf-engine.md`).
abstract final class PressureCodec {
  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  /// The number of pressure steps; a decoded value is within half a step
  /// (1 / 126) of the original.
  static const levels = 64;

  static String encode(List<List<double>> strokes) => [
    for (final stroke in strokes)
      String.fromCharCodes([
        for (final p in stroke)
          _alphabet.codeUnitAt((p.clamp(0.0, 1.0) * (levels - 1)).round()),
      ]),
  ].join(',');

  /// The pressures per stroke, or null where [text] is not a valid
  /// encoding (another writer, or a damaged file).
  static List<List<double>>? decode(String text) {
    final strokes = <List<double>>[];
    for (final part in text.split(',')) {
      final stroke = <double>[];
      for (final unit in part.codeUnits) {
        final level = _alphabet.indexOf(String.fromCharCode(unit));
        if (level < 0) return null;
        stroke.add(level / (levels - 1));
      }
      strokes.add(stroke);
    }
    return strokes;
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _nullableListEquals<T>(List<T>? a, List<T>? b) =>
    a == null || b == null ? a == b : _listEquals(a, b);
