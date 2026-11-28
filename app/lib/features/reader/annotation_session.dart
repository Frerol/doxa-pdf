// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:drift/drift.dart' show Value;

import '../library/document_identity.dart';
import '../library/library_database.dart';
import '../library/library_repository.dart';
import 'annotation_layer.dart';

/// Coordinates the overlay, durable log and editing instance (ADR-0013).
final class AnnotationSession {
  AnnotationSession({
    required this.library,
    required this.documentId,
    required this.location,
    required this.displayName,
    required String baseIdentity,
    required this.path,
    required this.engine,
    required this.document,
    required this.pageCount,
    required this.annotations,
    required this.reloadPage,
    required this.onError,
    this.saf,
    this.cacheDirectory,
    this.autosave = true,
    this.startTimer = Timer.new,
    this.strokeInProgress,
  }) : _identity = baseIdentity;

  static const quietPeriod = Duration(seconds: 5);

  final LibraryRepository library;
  final int documentId;
  final String location;
  final String displayName;
  final String path;
  final PdfEngine engine;
  final DocumentHandle document;
  final int pageCount;
  final DocumentAnnotations annotations;
  final void Function(int) reloadPage;
  final void Function(Object) onError;
  final PdfSaves? saf;
  final Future<String> Function()? cacheDirectory;
  final Timer Function(Duration, void Function()) startTimer;
  final bool Function()? strokeInProgress;

  final _history = AnnotationHistory();
  String _identity;
  String get baseIdentity => _identity;
  bool autosave;
  Timer? _timer;
  Future<void> _pending = Future.value();
  Future<bool>? _saving;
  Object? _syncError;
  bool _recoveryBlocked = false;
  final _unjournaled =
      <
        ({
          AnnotationCommand command,
          AnnotationCommand journalCommand,
          List<AnnotationCommand>? replacement,
        })
      >[];
  final _editedPages = <int>{};

  // PDFium can assign an /NM to a foreign annotation on its first update.
  // The editing instance uses it right away. The journal uses it once the
  // new name is on disk, because replay starts from the file.
  final _engineIds = <(int, String), String>{};
  final _savedIds = <(int, String), String>{};

  // The first command after a save must match PDFium's persisted values,
  // which can differ from the overlay in dates and coordinate precision.
  final _savedBefore = <(int, String), Annotation>{};
  List<AnnotationCommand>? _group;
  int _groupDepth = 0;
  bool _dirty = false;
  bool _disposed = false;

  bool _restoring = false;
  bool get hasUnsavedChanges => _dirty || _history.hasUnsavedChanges;
  bool readOnly = false;

  Future<bool> waitForSave() async {
    await _saving;
    return !_inputInProgress && !_restoring;
  }

  bool get _inputInProgress =>
      _group != null || (strokeInProgress?.call() ?? false);
  bool get isBusy => _inputInProgress || _saving != null || _restoring;
  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  JournalSessionsCompanion get _row => JournalSessionsCompanion.insert(
    documentId: Value(documentId),
    baseIdentity: _identity,
    location: journalLocationOf(location),
    displayName: displayName,
    startedAt: DateTime.now(),
  );

  Future<void> preparePage(int page) => annotations.load(page);

  /// Applies immediately when the affected pages are already loaded.
  Future<void> apply(AnnotationCommand command) async {
    final pages = command.pageIndexes;
    if (pages.any((page) => page < 0 || page >= pageCount)) {
      throw RangeError('An annotation targets a missing page');
    }
    if (pages.any((page) => !annotations.isLoaded(page))) {
      await Future.wait(pages.map(preparePage));
    }
    if (_saving case final saving?) await saving;
    if (_disposed || _restoring || _recoveryBlocked) {
      throw StateError('Session is unavailable');
    }
    annotations.apply(command);
    _history.record(command);
    if (_group case final group?) {
      group.add(command);
    } else {
      await _finish(command);
    }
  }

  /// Also brackets a stroke so autosave waits for the pointer to lift.
  void beginGroup() {
    if (_saving != null || _disposed || _restoring || _recoveryBlocked) {
      throw StateError('Session is unavailable');
    }
    _timer?.cancel();
    _group ??= [];
    _groupDepth++;
    _history.beginGroup();
  }

  Future<void> endGroup() async {
    _history.endGroup();
    if (--_groupDepth > 0) return;
    final commands = _group!;
    _group = null;
    if (commands.isEmpty) {
      _schedule();
    } else {
      await _finish(
        commands.length == 1 ? commands.single : CommandGroup(commands),
      );
    }
  }

  Future<void> undo() async {
    if (_saving case final saving?) await saving;
    if (_history.undo() case final command?) {
      annotations.apply(command);
      await _finish(command);
    }
  }

  Future<void> redo() async {
    if (_saving case final saving?) await saving;
    if (_history.redo() case final command?) {
      annotations.apply(command);
      await _finish(command);
    }
  }

  Future<void> _finish(
    AnnotationCommand command, {
    List<AnnotationCommand>? replacement,
  }) {
    _dirty = true;
    _editedPages.addAll(command.pageIndexes);
    _unjournaled.add((
      command: command,
      journalCommand: replacement == null ? _journalCommand(command) : command,
      replacement: replacement,
    ));
    _pending = _pending.then((_) => _flushEdits()).catchError(onError);
    _schedule();
    return _pending;
  }

  Future<void> _flushEdits() async {
    while (_unjournaled.isNotEmpty) {
      final edit = _unjournaled.first;
      if (edit.replacement case final replacement?) {
        await library.replaceJournal(_row, replacement);
      } else {
        await library.appendJournal(_row, edit.journalCommand);
      }
      _unjournaled.removeAt(0);
      if (_syncError == null) {
        try {
          await _sync(edit.command);
        } on Object catch (error) {
          // A decomposed command may have reached the engine only in part.
          // Keep logging edits, but require replay on a fresh instance to save.
          _syncError = error;
          onError(error);
        }
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_disposed && autosave && !_inputInProgress && _dirty) {
      _timer = startTimer(quietPeriod, backgroundSave);
    }
  }

  void onStrokeChanged() => _schedule();

  void updateAutosave(bool enabled) {
    if (autosave == enabled) return;
    autosave = enabled;
    _schedule();
  }

  void backgroundSave() {
    if (autosave) unawaited(save());
  }

  /// The caller confirms recovery before invoking this method.
  /// Returns the number of entries that did not fit a changed file.
  Future<int> restore(JournalSessionRow session) async {
    _restoring = true;
    try {
      return await _restore(session);
    } finally {
      _restoring = false;
    }
  }

  Future<int> _restore(JournalSessionRow session) async {
    final changed = session.baseIdentity != _identity;
    final commands = await library.journalCommands(session);
    final applied = <AnnotationCommand>[];
    final pages = {for (final command in commands) ...command.pageIndexes};
    await Future.wait([
      for (final page in pages)
        if (page >= 0 && page < pageCount) preparePage(page),
    ]);
    if (_disposed) return 0;
    final candidate = AnnotationStore([
      for (final page in pages) ...annotations.page(page).values,
    ]);
    for (final command in commands) {
      try {
        if (command.pageIndexes.any((p) => p < 0 || p >= pageCount)) {
          throw StateError('Journal page is missing');
        }
        candidate.apply(command);
        applied.add(command);
      } on StateError {
        if (!changed) rethrow;
      }
    }
    if (applied.isEmpty) {
      // Keep the original recovery log until the user discards it.
      _recoveryBlocked = true;
    } else {
      final group = CommandGroup(applied);
      annotations.apply(group);
      _history.record(group);
      if (changed || session.location != journalLocationOf(location)) {
        await _finish(group, replacement: applied);
      } else {
        _dirty = true;
        _editedPages.addAll(group.pageIndexes);
        _pending = _sync(group).catchError((Object error) {
          _syncError = error;
          onError(error);
        });
        _schedule();
        await _pending;
      }
    }
    return commands.length - applied.length;
  }

  Annotation _withId(Annotation annotation, Map<(int, String), String> ids) {
    final id = ids[(annotation.pageIndex, annotation.id)];
    if (id == null) return annotation;
    return AnnotationJson.decode({
      ...AnnotationJson.encode(annotation),
      'id': id,
    });
  }

  AnnotationCommand _journalCommand(AnnotationCommand command) {
    if (_savedBefore.isEmpty && _savedIds.isEmpty) return command;
    Annotation before(Annotation a) =>
        _savedBefore.remove((a.pageIndex, a.id)) ?? _withId(a, _savedIds);
    Annotation after(Annotation a) => _withId(a, _savedIds);
    return switch (command) {
      AddAnnotations(:final annotations) => AddAnnotations(
        annotations.map(after).toList(),
      ),
      DeleteAnnotations(:final annotations) => DeleteAnnotations(
        annotations.map(before).toList(),
      ),
      UpdateAnnotation(before: final a, after: final b) => UpdateAnnotation(
        before: before(a),
        after: after(b),
      ),
      MoveAnnotations(before: final from, after: final to) => CommandGroup([
        for (final (i, a) in from.indexed)
          UpdateAnnotation(before: before(a), after: after(to[i])),
      ]),
      EraseStrokeSegments(:final erasures) => EraseStrokeSegments([
        for (final e in erasures)
          StrokeErasure(
            before: e.before == null
                ? null
                : before(e.before!) as InkAnnotation,
            after: e.after == null ? null : after(e.after!) as InkAnnotation,
          ),
      ]),
      CommandGroup(:final commands) => CommandGroup(
        commands.map(_journalCommand).toList(),
      ),
    };
  }

  Future<void> _sync(AnnotationCommand command) async {
    switch (command) {
      case AddAnnotations(:final annotations):
        await engine.addAnnotations(document, annotations);
      case UpdateAnnotation(:final after):
        final written = await engine.updateAnnotation(
          document,
          _withId(after, _engineIds),
        );
        if (after.id != written.id) {
          _engineIds[(after.pageIndex, after.id)] = written.id;
        }
        if (!after.byDoxa && !_disposed) reloadPage(after.pageIndex);
      case DeleteAnnotations(:final annotations):
        for (final page in command.pageIndexes) {
          final deleted = annotations.where((a) => a.pageIndex == page);
          await engine.deleteAnnotations(document, page, [
            for (final a in deleted) _engineIds[(page, a.id)] ?? a.id,
          ]);
          if (deleted.any((a) => !a.byDoxa) && !_disposed) reloadPage(page);
        }
      case MoveAnnotations(:final before, :final after):
        for (final (i, annotation) in after.indexed) {
          await _sync(UpdateAnnotation(before: before[i], after: annotation));
        }
      case EraseStrokeSegments(:final erasures):
        for (final erasure in erasures) {
          await _sync(switch ((erasure.before, erasure.after)) {
            (null, final after!) => AddAnnotations([after]),
            (final before!, null) => DeleteAnnotations([before]),
            (final before!, final after!) => UpdateAnnotation(
              before: before,
              after: after,
            ),
          });
        }
      case CommandGroup(:final commands):
        for (final step in commands) {
          await _sync(step);
        }
    }
  }

  Future<bool> save() {
    if (_saving case final saving?) return saving;
    if (hasUnsavedChanges && (_disposed || _inputInProgress || _restoring)) {
      return Future.value(false);
    }
    if (!_dirty) return Future.value(true);
    _timer?.cancel();
    return _saving = _save().whenComplete(() => _saving = null);
  }

  Future<bool> _save() async {
    Directory? staging;
    try {
      await _pending;
      await _flushEdits();
      if (_syncError case final error?) throw error;
      final platform = saf;
      readOnly = platform != null && !await platform.canWrite(location);
      if (readOnly) {
        // TODO: Offer Save a copy, then clear the journal after verification.
        return false;
      }
      if (await engine.signatureCount(document) != 0) {
        throw StateError('Saving would invalidate digital signatures');
      }
      if (platform != null) {
        staging = await Directory(await cacheDirectory!())
            .createTemp('annotation-');
      }
      final destination = staging == null ? path : '${staging.path}/saved.pdf';
      final result = await engine.save(document, destination);
      if (result case SaveFailed(:final reason)) throw StateError(reason.name);
      final identity = await documentIdentity(destination);
      await platform?.writeBack(location, destination);
      final persisted = <(int, String), Annotation>{};
      for (final page in _editedPages) {
        final written = {
          for (final a in await engine.annotations(document, page)) a.id: a,
        };
        for (final a in annotations.page(page).values) {
          final key = (page, a.id);
          final saved = written[_engineIds[key] ?? a.id];
          if (saved != null && saved != a) persisted[key] = saved;
        }
      }
      await library.completeAnnotationSave(documentId, identity);
      _editedPages.clear();
      _savedBefore.addAll(persisted);
      _savedIds.addAll(_engineIds);
      _identity = identity;
      _history.markSaved();
      _dirty = false;
      return true;
    } on Object catch (error) {
      onError(error);
      return false;
    } finally {
      if (staging != null) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // Cache cleanup does not change the result of a verified save.
        }
      }
    }
  }

  /// Clears the recovery log when the tab is about to close.
  Future<void> discard() async {
    _timer?.cancel();
    await _saving;
    await _pending;
    await library.discardJournal(documentId);
    _dirty = false;
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _saving;
    await _pending;
  }
}
