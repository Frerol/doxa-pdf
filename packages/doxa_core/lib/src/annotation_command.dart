// SPDX-License-Identifier: GPL-3.0-or-later
import 'annotation.dart';
import 'annotation_json.dart';
import 'geometry.dart';

/// The annotations of one document in memory, one `Map<id, Annotation>`
/// per page. The app draws from it and the tests check it; commands change
/// it through [apply].
final class AnnotationStore {
  AnnotationStore([Iterable<Annotation> annotations = const []]) {
    for (final a in annotations) {
      final page = _pages.putIfAbsent(a.pageIndex, () => {});
      if (page.containsKey(a.id)) {
        throw ArgumentError.value(a.id, 'annotations', 'Duplicate id');
      }
      page[a.id] = a;
    }
  }

  final Map<int, Map<String, Annotation>> _pages = {};

  /// The annotations of page [pageIndex] by id; empty for a page without
  /// any. The map is read-only.
  Map<String, Annotation> page(int pageIndex) =>
      Map.unmodifiable(_pages[pageIndex] ?? const {});

  /// The pages that have at least one annotation, in no set order.
  Iterable<int> get pageIndexes => _pages.keys;

  /// A copy of every page's annotations, for comparing states.
  Map<int, Map<String, Annotation>> snapshot() => {
    for (final MapEntry(:key, :value) in _pages.entries) key: {...value},
  };

  /// Applies [command], all or nothing: if any step does not match what
  /// the store holds, a [StateError] is thrown and the store is unchanged.
  void apply(AnnotationCommand command) {
    switch (command) {
      case CommandGroup(:final commands):
        final applied = <AnnotationCommand>[];
        try {
          for (final c in commands) {
            apply(c);
            applied.add(c);
          }
        } catch (_) {
          for (final c in applied.reversed) {
            apply(c.inverse());
          }
          rethrow;
        }
      case _ChangeCommand():
        _applyChanges(command._changes);
    }
  }

  void _applyChanges(List<_Change> changes) {
    // Check every change against the state the earlier ones leave, before
    // touching the store.
    final pending = <(int, String), Annotation?>{};
    for (final change in changes) {
      final key = (change.pageIndex, change.id);
      final current = pending.containsKey(key)
          ? pending[key]
          : _pages[change.pageIndex]?[change.id];
      if (current != change.before) {
        throw StateError(
          current == null
              ? 'Annotation ${change.id} is not on page ${change.pageIndex}'
              : change.before == null
              ? 'Annotation ${change.id} already exists'
              : 'Annotation ${change.id} differs from the command',
        );
      }
      pending[key] = change.after;
    }
    for (final MapEntry(key: (pageIndex, id), :value) in pending.entries) {
      if (value == null) {
        final page = _pages[pageIndex];
        page?.remove(id);
        if (page != null && page.isEmpty) _pages.remove(pageIndex);
      } else {
        _pages.putIfAbsent(pageIndex, () => {})[id] = value;
      }
    }
  }
}

/// A change to a document's annotations (`docs/plan/03-architecture.md`
/// §5): small, serialisable and invertible. The undo history, the crash
/// journal and the engine sync all use the same command objects.
///
/// A command holds the annotations as they are before and after it, so it
/// applies only to the state it was made from, and [inverse] restores that
/// state exactly.
sealed class AnnotationCommand {
  const AnnotationCommand();

  /// The command that undoes this one.
  AnnotationCommand inverse();

  /// The pages whose annotations this command changes.
  Set<int> get pageIndexes;

  /// JSON values only, read back by [AnnotationCommand.fromJson].
  Map<String, Object?> toJson();

  /// Throws a [FormatException] for JSON that is not a command.
  static AnnotationCommand fromJson(Object? json) {
    final map = jsonMap(json, 'command');
    final type = jsonField<String>(map, 'type');
    List<Annotation> annotations(String key) => [
      for (final a in jsonField<List<Object?>>(map, key))
        AnnotationJson.decode(a),
    ];
    try {
      return switch (type) {
        AddAnnotations._type => AddAnnotations(annotations('annotations')),
        DeleteAnnotations._type => DeleteAnnotations(
          annotations('annotations'),
        ),
        UpdateAnnotation._type => UpdateAnnotation(
          before: AnnotationJson.decode(map['before']),
          after: AnnotationJson.decode(map['after']),
        ),
        MoveAnnotations._type => MoveAnnotations._(
          annotations('before'),
          annotations('after'),
          jsonNumber(map['dx'], 'dx'),
          jsonNumber(map['dy'], 'dy'),
        ),
        EraseStrokeSegments._type => EraseStrokeSegments([
          for (final e in jsonField<List<Object?>>(map, 'erasures'))
            _erasureFromJson(jsonMap(e, 'erasure')),
        ]),
        CommandGroup._type => CommandGroup([
          for (final c in jsonField<List<Object?>>(map, 'commands'))
            fromJson(c),
        ]),
        _ => throw FormatException('Unknown command type', type),
      };
    } on ArgumentError catch (e) {
      throw FormatException('Invalid command: ${e.message}', json);
    }
  }
}

/// One annotation as it is before and after a command; null means absent.
final class _Change {
  _Change(this.before, this.after)
    : assert(before != null || after != null, 'A change changes something'),
      assert(
        before == null ||
            after == null ||
            (before.id == after.id && before.pageIndex == after.pageIndex),
        'A change keeps the id and the page',
      );

  final Annotation? before;
  final Annotation? after;

  String get id => (before ?? after)!.id;
  int get pageIndex => (before ?? after)!.pageIndex;
}

sealed class _ChangeCommand extends AnnotationCommand {
  const _ChangeCommand();

  List<_Change> get _changes;

  @override
  Set<int> get pageIndexes => {for (final c in _changes) c.pageIndex};
}

void _requireNotEmpty(List<Object?> list, String name) {
  if (list.isEmpty) throw ArgumentError.value(list, name, 'Must not be empty');
}

void _requireSameIdAndPage(Annotation before, Annotation after) {
  if (before.id != after.id || before.pageIndex != after.pageIndex) {
    throw ArgumentError('Before and after must share the id and the page');
  }
}

List<Map<String, Object?>> _encodeAll(List<Annotation> annotations) => [
  for (final a in annotations) AnnotationJson.encode(a),
];

/// Adds new annotations, on one page or several.
final class AddAnnotations extends _ChangeCommand {
  AddAnnotations(List<Annotation> annotations)
    : annotations = List.unmodifiable(annotations) {
    _requireNotEmpty(annotations, 'annotations');
  }

  static const _type = 'add';

  final List<Annotation> annotations;

  @override
  List<_Change> get _changes => [for (final a in annotations) _Change(null, a)];

  @override
  DeleteAnnotations inverse() => DeleteAnnotations(annotations);

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'annotations': _encodeAll(annotations),
  };
}

/// Deletes annotations, keeping them whole so [inverse] can add them back.
final class DeleteAnnotations extends _ChangeCommand {
  DeleteAnnotations(List<Annotation> annotations)
    : annotations = List.unmodifiable(annotations) {
    _requireNotEmpty(annotations, 'annotations');
  }

  static const _type = 'delete';

  /// The annotations as they were when deleted.
  final List<Annotation> annotations;

  @override
  List<_Change> get _changes => [for (final a in annotations) _Change(a, null)];

  @override
  AddAnnotations inverse() => AddAnnotations(annotations);

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'annotations': _encodeAll(annotations),
  };
}

/// Changes one annotation (colour, opacity, note, kind…) in place.
final class UpdateAnnotation extends _ChangeCommand {
  UpdateAnnotation({required this.before, required this.after}) {
    _requireSameIdAndPage(before, after);
  }

  static const _type = 'update';

  final Annotation before;
  final Annotation after;

  @override
  List<_Change> get _changes => [_Change(before, after)];

  @override
  UpdateAnnotation inverse() => UpdateAnnotation(before: after, after: before);

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'before': AnnotationJson.encode(before),
    'after': AnnotationJson.encode(after),
  };
}

/// Moves annotations of a page by ([dx], [dy]) in PDF user space, as a
/// lasso move does (FR-INK-011).
///
/// It keeps both [before] and [after], because adding the offset and then
/// subtracting it does not always give back the same doubles. [dx] and
/// [dy] tell the engine that this is a translation, so it can move an
/// appearance stream and geometry this model does not hold (the `/L` of a
/// line, the `/Vertices` of a polygon) instead of rebuilding them.
final class MoveAnnotations extends _ChangeCommand {
  /// Moves [annotations], as they are now, by ([dx], [dy]).
  factory MoveAnnotations(
    List<Annotation> annotations, {
    required double dx,
    required double dy,
  }) => MoveAnnotations._(
    annotations,
    [for (final a in annotations) translateAnnotation(a, dx, dy)],
    dx,
    dy,
  );

  MoveAnnotations._(
    List<Annotation> before,
    List<Annotation> after,
    this.dx,
    this.dy,
  ) : before = List.unmodifiable(before),
      after = List.unmodifiable(after) {
    _requireNotEmpty(before, 'before');
    if (before.length != after.length) {
      throw ArgumentError('Before and after must have the same length');
    }
    for (var i = 0; i < before.length; i++) {
      _requireSameIdAndPage(before[i], after[i]);
    }
  }

  static const _type = 'move';

  final List<Annotation> before;
  final List<Annotation> after;
  final double dx;
  final double dy;

  @override
  List<_Change> get _changes => [
    for (var i = 0; i < before.length; i++) _Change(before[i], after[i]),
  ];

  @override
  MoveAnnotations inverse() => MoveAnnotations._(after, before, -dx, -dy);

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'before': _encodeAll(before),
    'after': _encodeAll(after),
    'dx': dx,
    'dy': dy,
  };
}

/// [annotation] moved by ([dx], [dy]): its `/Rect` and the geometry this
/// model holds (quads, ink points).
Annotation translateAnnotation(Annotation annotation, double dx, double dy) {
  PdfPoint p(PdfPoint p) => PdfPoint(p.x + dx, p.y + dy);
  final r = annotation.rect;
  final rect = PdfRect(r.left + dx, r.bottom + dy, r.right + dx, r.top + dy);
  return switch (annotation) {
    TextMarkup a => TextMarkup(
      id: a.id,
      pageIndex: a.pageIndex,
      rect: rect,
      kind: a.kind,
      quads: [
        for (final q in a.quads) PdfQuad(p(q.p1), p(q.p2), p(q.p3), p(q.p4)),
      ],
      text: a.text,
      color: a.color,
      opacity: a.opacity,
      author: a.author,
      contents: a.contents,
      modified: a.modified,
      flags: a.flags,
      byDoxa: a.byDoxa,
    ),
    InkAnnotation a => InkAnnotation(
      id: a.id,
      pageIndex: a.pageIndex,
      rect: rect,
      strokes: [
        for (final s in a.strokes)
          InkStroke([for (final q in s.points) p(q)], pressures: s.pressures),
      ],
      width: a.width,
      tool: a.tool,
      color: a.color,
      opacity: a.opacity,
      author: a.author,
      contents: a.contents,
      modified: a.modified,
      flags: a.flags,
      byDoxa: a.byDoxa,
    ),
    OtherAnnotation a => OtherAnnotation(
      id: a.id,
      pageIndex: a.pageIndex,
      rect: rect,
      subtype: a.subtype,
      color: a.color,
      opacity: a.opacity,
      author: a.author,
      contents: a.contents,
      modified: a.modified,
      flags: a.flags,
      byDoxa: a.byDoxa,
    ),
  };
}

/// What the partial eraser did to one Ink annotation (FR-INK-005).
final class StrokeErasure {
  /// [before] is the whole annotation, which keeps the removed points.
  /// [after] holds the strokes that are left, split where the eraser cut
  /// them, or is null where nothing is left and the annotation goes.
  /// One of the two may be null in an [EraseStrokeSegments.inverse].
  StrokeErasure({required this.before, required this.after}) {
    if (before == null && after == null) {
      throw ArgumentError('An erasure needs a before or an after');
    }
    if (before != null && after != null) {
      _requireSameIdAndPage(before!, after!);
    }
  }

  final InkAnnotation? before;
  final InkAnnotation? after;

  StrokeErasure get _inverse => StrokeErasure(before: after, after: before);
}

StrokeErasure _erasureFromJson(Map<String, Object?> map) {
  InkAnnotation? ink(String key) {
    final json = map[key];
    if (json == null) return null;
    final annotation = AnnotationJson.decode(json);
    return annotation is InkAnnotation
        ? annotation
        : throw FormatException('An erasure holds ink', json);
  }

  return StrokeErasure(before: ink('before'), after: ink('after'));
}

/// One pass of the partial eraser, over one or more Ink annotations.
///
/// Its [inverse] is an [EraseStrokeSegments] whose erasures run from
/// after to before, so it puts back the removed points and the annotations
/// the eraser removed whole.
final class EraseStrokeSegments extends _ChangeCommand {
  EraseStrokeSegments(List<StrokeErasure> erasures)
    : erasures = List.unmodifiable(erasures) {
    _requireNotEmpty(erasures, 'erasures');
  }

  static const _type = 'erase';

  final List<StrokeErasure> erasures;

  @override
  List<_Change> get _changes => [
    for (final e in erasures) _Change(e.before, e.after),
  ];

  @override
  EraseStrokeSegments inverse() =>
      EraseStrokeSegments([for (final e in erasures) e._inverse]);

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'erasures': [
      for (final e in erasures)
        {
          'before': e.before == null ? null : AnnotationJson.encode(e.before!),
          'after': e.after == null ? null : AnnotationJson.encode(e.after!),
        },
    ],
  };
}

/// Several commands that undo and redo as one step, such as the moves of
/// one lasso drag. They apply in order.
final class CommandGroup extends AnnotationCommand {
  CommandGroup(List<AnnotationCommand> commands)
    : commands = List.unmodifiable(commands) {
    _requireNotEmpty(commands, 'commands');
  }

  static const _type = 'group';

  final List<AnnotationCommand> commands;

  @override
  CommandGroup inverse() =>
      CommandGroup([for (final c in commands.reversed) c.inverse()]);

  @override
  Set<int> get pageIndexes => {for (final c in commands) ...c.pageIndexes};

  @override
  Map<String, Object?> toJson() => {
    'type': _type,
    'commands': [for (final c in commands) c.toJson()],
  };
}
