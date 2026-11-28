// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:doxa_core/doxa_core.dart';
import 'package:test/test.dart';

OtherAnnotation _note(int n) => OtherAnnotation(
  id: 'doxa:$n',
  pageIndex: 0,
  rect: PdfRect(n.toDouble(), 0, n + 1, 1),
  subtype: 'Text',
);

/// Applies [command] to [store] and records it, as the app does.
void _run(
  AnnotationStore store,
  AnnotationHistory history,
  AnnotationCommand command,
) {
  store.apply(command);
  history.record(command);
}

void main() {
  group('AnnotationHistory (FR-ANNO-001)', () {
    test('the step past the cap drops the oldest, and undo still works', () {
      final store = AnnotationStore();
      final history = AnnotationHistory();
      const steps = AnnotationHistory.defaultCapacity + 1;
      for (var i = 0; i < steps; i++) {
        _run(store, history, AddAnnotations([_note(i)]));
      }
      var undone = 0;
      while (history.canUndo) {
        store.apply(history.undo()!);
        undone++;
      }
      expect(undone, AnnotationHistory.defaultCapacity);
      // Only the first, dropped step is left.
      expect(store.page(0).keys, ['doxa:0']);
      while (history.canRedo) {
        store.apply(history.redo()!);
      }
      expect(store.page(0).length, steps);
    });

    test('a new command clears redo', () {
      final store = AnnotationStore();
      final history = AnnotationHistory();
      _run(store, history, AddAnnotations([_note(1)]));
      store.apply(history.undo()!);
      expect(history.canRedo, isTrue);
      _run(store, history, AddAnnotations([_note(2)]));
      expect(history.canRedo, isFalse);
      expect(history.redo(), isNull);
    });

    test('a group is one step', () {
      final store = AnnotationStore([_note(1)]);
      final history = AnnotationHistory();
      final start = store.snapshot();
      history.beginGroup();
      // One lasso drag, recorded as it moves.
      var current = store.page(0).values.toList();
      for (var i = 0; i < 5; i++) {
        final move = MoveAnnotations(current, dx: 1.5, dy: 0.25);
        _run(store, history, move);
        current = move.after;
      }
      history.beginGroup(); // a nested group joins the outer one
      _run(store, history, AddAnnotations([_note(2)]));
      history.endGroup();
      expect(history.canUndo, isFalse, reason: 'the group is still open');
      expect(history.hasUnsavedChanges, isTrue);
      history.endGroup();

      store.apply(history.undo()!);
      expect(store.snapshot(), equals(start));
      expect(history.canUndo, isFalse);
    });

    test('an empty group adds no step', () {
      final history = AnnotationHistory()
        ..beginGroup()
        ..endGroup();
      expect(history.canUndo, isFalse);
      expect(history.hasUnsavedChanges, isFalse);
    });

    group('unsaved changes', () {
      test('follow the saved marker through undo and redo', () {
        final store = AnnotationStore();
        final history = AnnotationHistory();
        expect(history.hasUnsavedChanges, isFalse);
        _run(store, history, AddAnnotations([_note(1)]));
        expect(history.hasUnsavedChanges, isTrue);
        store.apply(history.undo()!);
        expect(history.hasUnsavedChanges, isFalse, reason: 'back as opened');

        store.apply(history.redo()!);
        history.markSaved();
        expect(history.hasUnsavedChanges, isFalse);
        store.apply(history.undo()!);
        expect(history.hasUnsavedChanges, isTrue);
        store.apply(history.redo()!);
        expect(history.hasUnsavedChanges, isFalse);
      });

      test('stay once the saved state is no longer reachable', () {
        final store = AnnotationStore();
        final history = AnnotationHistory();
        _run(store, history, AddAnnotations([_note(1)]));
        history.markSaved();
        store.apply(history.undo()!);
        // A different step at the same depth as the save.
        _run(store, history, AddAnnotations([_note(2)]));
        expect(history.hasUnsavedChanges, isTrue);
        store.apply(history.undo()!);
        expect(history.hasUnsavedChanges, isTrue);
      });

      test('stay when the cap drops the saved state', () {
        final store = AnnotationStore();
        final history = AnnotationHistory(capacity: 2);
        for (var i = 0; i < 3; i++) {
          _run(store, history, AddAnnotations([_note(i)]));
        }
        while (history.canUndo) {
          store.apply(history.undo()!);
        }
        // One note is left, so this is not the file as opened.
        expect(store.page(0), isNotEmpty);
        expect(history.hasUnsavedChanges, isTrue);
      });
    });
  });
}
