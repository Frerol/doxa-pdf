// SPDX-License-Identifier: GPL-3.0-or-later
import 'annotation_command.dart';

/// The undo and redo history of one document's annotations (FR-ANNO-001).
///
/// It holds commands only; the caller applies them to the
/// [AnnotationStore], the engine and the journal. [record] takes a command
/// that has just been applied; [undo] and [redo] return the command the
/// caller must apply next.
final class AnnotationHistory {
  /// Keeps at most [capacity] undo steps; the oldest goes first.
  AnnotationHistory({this.capacity = defaultCapacity})
    : assert(capacity > 0, 'The history keeps at least one step');

  /// FR-ANNO-001 asks for at least 100 steps.
  static const defaultCapacity = 100;

  final int capacity;

  final List<AnnotationCommand> _undo = [];
  final List<AnnotationCommand> _redo = [];

  /// The length of [_undo] when the document was last saved, or null when
  /// that state can no longer be reached by undo or redo. A new history
  /// starts at the state of the file as opened.
  int? _savedDepth = 0;

  /// The commands of the open group, or null when none is open.
  List<AnnotationCommand>? _group;
  int _groupDepth = 0;

  bool get canUndo => _group == null && _undo.isNotEmpty;
  bool get canRedo => _group == null && _redo.isNotEmpty;

  /// Whether the annotations differ from the last save (or from the file
  /// as opened, before any save).
  bool get hasUnsavedChanges =>
      _savedDepth != _undo.length || (_group?.isNotEmpty ?? false);

  /// Records [command], already applied, as a new step, or as part of the
  /// open group. It clears redo.
  void record(AnnotationCommand command) {
    final group = _group;
    if (group != null) {
      group.add(command);
      return;
    }
    _push(command);
  }

  /// Starts a group: the commands recorded until the matching [endGroup]
  /// become one step, as a lasso drag does. Groups may nest; only the
  /// outermost one makes a step.
  void beginGroup() {
    _groupDepth++;
    _group ??= [];
  }

  /// Ends the group [beginGroup] started. A group without commands adds
  /// no step.
  void endGroup() {
    if (_groupDepth == 0) throw StateError('No group is open');
    if (--_groupDepth > 0) return;
    final commands = _group!;
    _group = null;
    if (commands.isEmpty) return;
    _push(commands.length == 1 ? commands.single : CommandGroup(commands));
  }

  /// Steps back: returns the command that undoes the last step, for the
  /// caller to apply, or null when there is nothing to undo.
  AnnotationCommand? undo() {
    _requireNoGroup();
    if (_undo.isEmpty) return null;
    final command = _undo.removeLast();
    _redo.add(command);
    return command.inverse();
  }

  /// Steps forward again: returns the command to apply, or null when there
  /// is nothing to redo.
  AnnotationCommand? redo() {
    _requireNoGroup();
    if (_redo.isEmpty) return null;
    final command = _redo.removeLast();
    _undo.add(command);
    return command;
  }

  /// Marks the current state as saved.
  void markSaved() {
    _requireNoGroup();
    _savedDepth = _undo.length;
  }

  void _push(AnnotationCommand command) {
    // A saved state among the redo steps is gone once redo is cleared.
    if (_savedDepth != null && _savedDepth! > _undo.length) _savedDepth = null;
    _redo.clear();
    _undo.add(command);
    if (_undo.length > capacity) {
      _undo.removeAt(0);
      // The saved state was before the dropped step: it is gone too.
      _savedDepth = _savedDepth == null || _savedDepth == 0
          ? null
          : _savedDepth! - 1;
    }
  }

  void _requireNoGroup() {
    if (_group != null) throw StateError('A group is open');
  }
}
