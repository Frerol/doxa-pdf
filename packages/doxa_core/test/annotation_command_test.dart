// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:math';

import 'package:doxa_core/doxa_core.dart';
import 'package:test/test.dart';

/// Makes random annotations and random commands that are valid for the
/// state of a store.
final class _Gen {
  _Gen(int seed) : random = Random(seed);

  final Random random;
  var _next = 0;

  double _coord() => random.nextDouble() * 600;
  PdfPoint _point() => PdfPoint(_coord(), _coord());

  Annotation annotation(int pageIndex) {
    final id = 'doxa:${_next++}';
    final color = random.nextBool() ? random.nextInt(0x1000000) : null;
    final modified = random.nextBool()
        ? DateTime.utc(2026, 11, 27, 10, 0, random.nextInt(60), 0, 123)
        : null;
    switch (random.nextInt(3)) {
      case 0:
        return TextMarkup(
          id: id,
          pageIndex: pageIndex,
          kind: MarkupKind.values[random.nextInt(MarkupKind.values.length)],
          quads: [
            for (var i = 0; i <= random.nextInt(3); i++)
              PdfQuad(_point(), _point(), _point(), _point()),
          ],
          text: random.nextBool() ? 'naïve “text” $id' : null,
          color: color,
          opacity: random.nextDouble(),
          contents: random.nextBool() ? 'note' : null,
          modified: modified,
          byDoxa: true,
        );
      case 1:
        return InkAnnotation(
          id: id,
          pageIndex: pageIndex,
          strokes: [for (var i = 0; i <= random.nextInt(3); i++) _stroke()],
          width: 0.5 + random.nextDouble() * 4,
          tool: InkTool.values[random.nextInt(InkTool.values.length)],
          color: color,
          opacity: random.nextDouble(),
          author: random.nextBool() ? 'Reader' : null,
          modified: modified,
          byDoxa: true,
        );
      default:
        return OtherAnnotation(
          id: id,
          pageIndex: pageIndex,
          rect: PdfRect(_coord(), _coord(), _coord(), _coord()),
          subtype: 'Square',
          color: color,
          flags: Annotation.printFlag | Annotation.hiddenFlag,
        );
    }
  }

  InkStroke _stroke() {
    final n = 2 + random.nextInt(8);
    return InkStroke(
      [for (var i = 0; i < n; i++) _point()],
      pressures: random.nextBool()
          ? [for (var i = 0; i < n; i++) random.nextDouble()]
          : null,
    );
  }

  List<T> _pick<T>(List<T> all) {
    final picked = [
      for (final a in all)
        if (random.nextInt(3) == 0) a,
    ];
    return picked.isEmpty ? [all[random.nextInt(all.length)]] : picked;
  }

  /// A command that applies to [store], or null when none fits.
  AnnotationCommand? command(AnnotationStore store, {bool allowGroup = true}) {
    final all = [for (final p in store.pageIndexes) ...store.page(p).values];
    final ink = all.whereType<InkAnnotation>().toList();
    final choice = random.nextInt(allowGroup ? 6 : 5);
    if (all.isEmpty || choice == 0) {
      return AddAnnotations([
        for (var i = 0; i <= random.nextInt(3); i++)
          annotation(random.nextInt(4)),
      ]);
    }
    switch (choice) {
      case 1:
        return DeleteAnnotations(_pick(all));
      case 2:
        final before = all[random.nextInt(all.length)];
        final after = switch (before) {
          TextMarkup a => a.copyWith(
            kind: MarkupKind.underline,
            color: 0x00ff00,
            contents: 'edited',
          ),
          InkAnnotation a => a.copyWith(width: a.width + 1, opacity: 0.5),
          OtherAnnotation a => a.copyWith(contents: 'edited'),
        };
        return UpdateAnnotation(before: before, after: after);
      case 3:
        final page = all[random.nextInt(all.length)].pageIndex;
        return MoveAnnotations(
          _pick(store.page(page).values.toList()),
          dx: random.nextDouble() * 10 - 5,
          dy: random.nextDouble() * 10 - 5,
        );
      case 4:
        if (ink.isEmpty) return null;
        return EraseStrokeSegments([
          for (final a in _pick(ink))
            StrokeErasure(
              before: a,
              // Either the whole annotation goes, or its first stroke is
              // cut in two and the rest stays.
              after: a.strokes.first.points.length < 2 || random.nextBool()
                  ? null
                  : a.copyWith(
                      strokes: [
                        InkStroke(a.strokes.first.points.sublist(0, 1)),
                        InkStroke(a.strokes.first.points.sublist(1)),
                        ...a.strokes.skip(1),
                      ],
                    ),
            ),
        ]);
      default:
        // A group of steps, each made from the state the earlier ones
        // leave, applied to a scratch copy.
        final scratch = AnnotationStore([
          for (final p in store.pageIndexes) ...store.page(p).values,
        ]);
        final commands = <AnnotationCommand>[];
        for (var i = 0; i < 2 + random.nextInt(3); i++) {
          final c = command(scratch, allowGroup: false);
          if (c == null) continue;
          scratch.apply(c);
          commands.add(c);
        }
        return commands.isEmpty ? null : CommandGroup(commands);
    }
  }
}

AnnotationCommand _roundTrip(AnnotationCommand command) =>
    AnnotationCommand.fromJson(jsonDecode(jsonEncode(command.toJson())));

void main() {
  group('commands and history (FR-ANNO-001)', () {
    test('undoing every step restores the start, redoing it the end', () {
      for (var seed = 0; seed < 200; seed++) {
        final gen = _Gen(seed);
        final store = AnnotationStore([
          for (var i = 0; i < gen.random.nextInt(4); i++)
            gen.annotation(gen.random.nextInt(3)),
        ]);
        final history = AnnotationHistory();
        final start = store.snapshot();
        var steps = 0;
        while (steps < 1 + gen.random.nextInt(40)) {
          final command = gen.command(store);
          if (command == null) continue;
          // What the journal reads back must do the same as the original.
          store.apply(_roundTrip(command));
          history.record(command);
          steps++;
        }
        final end = store.snapshot();

        while (history.canUndo) {
          store.apply(history.undo()!);
        }
        expect(store.snapshot(), equals(start), reason: 'seed $seed');
        while (history.canRedo) {
          store.apply(history.redo()!);
        }
        expect(store.snapshot(), equals(end), reason: 'seed $seed');
      }
    });

    test('every command and its inverse survive a JSON round trip', () {
      final gen = _Gen(7);
      final seen = <Type>{};
      final store = AnnotationStore();
      for (var i = 0; i < 300; i++) {
        final command = gen.command(store);
        if (command == null) continue;
        for (final c in [command, command.inverse()]) {
          seen.add(c.runtimeType);
          final decoded = _roundTrip(c);
          expect(decoded.runtimeType, c.runtimeType);
          expect(decoded.toJson(), equals(c.toJson()));
          expect(decoded.pageIndexes, c.pageIndexes);
        }
        // Applying the decoded copy leaves the same state as the original.
        final copy = AnnotationStore([
          for (final p in store.pageIndexes) ...store.page(p).values,
        ])..apply(_roundTrip(command));
        store.apply(command);
        expect(copy.snapshot(), equals(store.snapshot()));
      }
      expect(seen, {
        AddAnnotations,
        DeleteAnnotations,
        UpdateAnnotation,
        MoveAnnotations,
        EraseStrokeSegments,
        CommandGroup,
      });
    });

    test('a command that does not match the store changes nothing', () {
      final gen = _Gen(1);
      final a = gen.annotation(0), b = gen.annotation(0);
      final store = AnnotationStore([a]);
      final before = store.snapshot();
      for (final command in [
        // b is added, then a is added a second time.
        AddAnnotations([b, a]),
        // a is deleted, then b, which is not there.
        DeleteAnnotations([a, b]),
        // The second step of the group fails after the first applied.
        CommandGroup([
          DeleteAnnotations([a]),
          DeleteAnnotations([a]),
        ]),
        // The store holds a, not the state the update was made from.
        UpdateAnnotation(
          before: translateAnnotation(a, 1, 0),
          after: translateAnnotation(a, 2, 0),
        ),
      ]) {
        expect(() => store.apply(command), throwsStateError);
        expect(store.snapshot(), equals(before));
      }
    });

    test('a move shifts the geometry and only the geometry', () {
      final markup = TextMarkup(
        id: 'doxa:m',
        pageIndex: 2,
        kind: MarkupKind.highlight,
        quads: [PdfQuad.fromRect(const PdfRect(10, 20, 110, 32))],
        color: 0xffd400,
      );
      final moved =
          MoveAnnotations([markup], dx: 5, dy: -3).after.single as TextMarkup;
      expect(moved.rect, const PdfRect(15, 17, 115, 29));
      expect(
        moved.quads.single,
        PdfQuad.fromRect(const PdfRect(15, 17, 115, 29)),
      );
      expect(
        (moved.id, moved.pageIndex, moved.kind, moved.color),
        (markup.id, markup.pageIndex, markup.kind, markup.color),
      );
    });

    test('JSON that is not a command is rejected', () {
      final good = AddAnnotations([_Gen(2).annotation(0)]).toJson();
      for (final bad in <Object?>[
        null,
        'add',
        {'type': 'teleport'},
        {...good, 'annotations': <Object?>[]},
        {
          ...good,
          'annotations': [
            {
              ...(good['annotations'] as List).single as Map,
              'rect': [1, 2],
            },
          ],
        },
        {
          'type': 'update',
          'before': AnnotationJson.encode(_Gen(3).annotation(0)),
          'after': AnnotationJson.encode(_Gen(4).annotation(1)),
        },
      ]) {
        expect(
          () => AnnotationCommand.fromJson(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });
  });
}
