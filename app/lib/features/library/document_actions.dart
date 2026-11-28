// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:doxa_platform/doxa_platform.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'favorite_button.dart';
import 'folder_page.dart';
import 'library_repository.dart';

/// The file name to rename [current] to from what the user [typed], or null
/// when it is not a usable new name: empty, unchanged, `.` or `..`, or with
/// a `/` or a NUL. The `.pdf` extension of [current] is added back when the
/// user left it out, so the file keeps opening as a PDF.
String? renameTarget(String typed, String current) {
  var name = typed.trim();
  if (name.isEmpty || name == '.' || name == '..') return null;
  if (name.contains('/') || name.contains('\u0000')) return null;
  const pdf = '.pdf';
  final hadPdf = current.toLowerCase().endsWith(pdf);
  if (hadPdf && !name.toLowerCase().endsWith(pdf)) name = '$name$pdf';
  return name == current ? null : name;
}

/// The part of [name] the rename field selects: the name without `.pdf`.
String _stem(String name) => name.toLowerCase().endsWith('.pdf')
    ? name.substring(0, name.length - 4)
    : name;

/// Where a document is moved: a folder of a library folder tree, or the
/// tree's root when [documentId] is null.
typedef MoveTarget = ({String treeUri, String? documentId});

/// Rename, move and delete for the library's lists (FR-FILE-011): asks the
/// user, changes the file through [files], keeps the library in step, and
/// explains failures in a snack bar.
final class DocumentActions {
  DocumentActions({
    required this.files,
    this.library,
    this.thumbnails,
    this.folders,
  });

  final DocumentFiles files;
  final LibraryRepository? library;
  final ThumbnailStore? thumbnails;
  final LibraryFolders? folders;

  /// Rename and delete work on documents the system provides.
  bool canChange(String? uri) =>
      uri != null && Uri.tryParse(uri)?.scheme == 'content';

  /// Move works on documents in a library folder.
  bool canMove(String? uri) =>
      uri != null && library != null && folders != null && isInFolderTree(uri);

  /// Renames the document at [uri], now called [name]. True when it changed.
  Future<bool> rename(
    BuildContext context, {
    required String uri,
    required String name,
  }) async {
    final typed = await showDialog<String>(
      context: context,
      builder: (_) => RenameDialog(current: name),
    );
    if (typed == null || !context.mounted) return false;
    PlatformMovedDocument? renamed;
    final changed = await _change(context, () async {
      renamed = await files.rename(uri, typed);
      await _relocate(uri, renamed!);
    });
    if (changed && context.mounted) _warnIfLost(context, renamed!);
    return changed;
  }

  /// Moves the document at [uri] to a folder the user picks. True when it
  /// moved.
  Future<bool> move(BuildContext context, {required String uri}) async =>
      await moveAll(context, [uri]) > 0;

  /// Moves the documents at [uris], all on one storage, to one folder the
  /// user picks. Returns how many moved; a document already in that folder
  /// does not count.
  Future<int> moveAll(BuildContext context, List<String> uris) async {
    final library = this.library;
    final folders = this.folders;
    if (library == null || folders == null || uris.isEmpty) return 0;
    final authority = Uri.parse(uris.first).authority;
    final roots = [
      for (final folder in await library.watchFolders().first)
        if (Uri.tryParse(folder.treeUri)?.authority == authority) folder,
    ];
    if (!context.mounted) return 0;
    if (roots.isEmpty) {
      _show(context, AppLocalizations.of(context).moveNoFolders);
      return 0;
    }
    final target = await Navigator.of(context).push<MoveTarget>(
      MaterialPageRoute(
        builder: (_) => MoveTargetPage(roots: roots, folders: folders),
      ),
    );
    if (target == null || !context.mounted) return 0;
    var moved = 0;
    var lost = false;
    final errors = <DocumentFileError>[];
    for (final uri in uris) {
      final error = await _attempt(() async {
        final result = await files.move(
          uri,
          targetTreeUri: target.treeUri,
          targetDocumentId: target.documentId,
        );
        await _relocate(uri, result);
        // Moving into the folder it is already in changes nothing.
        if (result.uri != uri) moved++;
        lost |= !result.persisted;
      });
      if (error != null) errors.add(error);
    }
    if (context.mounted) {
      _report(context, errors, uris.length);
      if (lost && errors.isEmpty) {
        _show(context, AppLocalizations.of(context).documentNotReopenable);
      }
    }
    return moved;
  }

  /// Deletes the document at [uri], called [name], after the user confirms.
  /// True when it was deleted.
  Future<bool> delete(
    BuildContext context, {
    required String uri,
    required String name,
  }) async => await deleteAll(context, [(uri: uri, name: name)]) > 0;

  /// Deletes [documents] after one confirmation. Returns how many were
  /// deleted.
  Future<int> deleteAll(
    BuildContext context,
    List<({String uri, String name})> documents,
  ) async {
    if (documents.isEmpty) return 0;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          documents.length == 1
              ? l10n.deleteDocumentTitle(documents.single.name)
              : l10n.deleteDocumentsTitle(documents.length),
        ),
        content: Text(
          documents.length == 1
              ? l10n.deleteDocumentMessage
              : l10n.deleteDocumentsMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteDocument),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return 0;
    var deleted = 0;
    final errors = <DocumentFileError>[];
    for (final document in documents) {
      final error = await _attempt(() async {
        await files.delete(document.uri);
        deleted++;
        final identities =
            await library?.forgetDeleted(document.uri) ?? const [];
        for (final identity in identities) {
          await thumbnails?.delete(identity);
        }
      });
      if (error != null) errors.add(error);
    }
    if (context.mounted) _report(context, errors, documents.length);
    return deleted;
  }

  Future<void> _relocate(String uri, PlatformMovedDocument moved) async {
    await library?.relocate(
      uri,
      newUri: moved.persisted ? moved.uri : null,
      displayName: moved.displayName,
    );
  }

  /// Tells the user when the library can no longer reopen the document.
  void _warnIfLost(BuildContext context, PlatformMovedDocument moved) {
    if (!moved.persisted) {
      _show(context, AppLocalizations.of(context).documentNotReopenable);
    }
  }

  /// Runs [action]; true when it succeeded, otherwise says why.
  Future<bool> _change(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final error = await _attempt(action);
    if (error != null && context.mounted) _report(context, [error], 1);
    return error == null;
  }

  /// Runs [action]; null when it succeeded, otherwise why it failed.
  Future<DocumentFileError?> _attempt(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } on DocumentFileException catch (error) {
      return error.error;
    } on Object catch (error) {
      debugPrint('Doxa: file action failed: $error');
      return DocumentFileError.failed;
    }
  }

  /// Explains the [errors] of an action on [total] documents: the cause when
  /// there is one document, how many failed when there are more.
  void _report(
    BuildContext context,
    List<DocumentFileError> errors,
    int total,
  ) {
    if (errors.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    if (total > 1) {
      _show(context, l10n.fileActionsFailed(errors.length, total));
      return;
    }
    _show(context, switch (errors.single) {
      DocumentFileError.missing => l10n.fileMissing,
      DocumentFileError.permissionLost => l10n.fileActionPermissionLost,
      DocumentFileError.unsupported => l10n.fileActionUnsupported,
      DocumentFileError.failed => l10n.fileActionFailed,
    });
  }

  void _show(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Asks for a new file name; pops it, already checked by [renameTarget].
class RenameDialog extends StatefulWidget {
  const RenameDialog({super.key, required this.current});

  final String current;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final _name = TextEditingController(text: widget.current)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: _stem(widget.current).length,
    );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _target => renameTarget(_name.text, widget.current);

  void _submit() {
    if (_target case final name?) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.renameDocumentTitle),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.renameDocumentName),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: _target == null ? null : _submit,
          child: Text(l10n.renameDocument),
        ),
      ],
    );
  }
}

/// Picks the folder to move a document into (FR-FILE-011): the library
/// folders [roots] first, then their subfolders level by level. Pops the
/// chosen [MoveTarget].
class MoveTargetPage extends StatefulWidget {
  const MoveTargetPage({super.key, required this.roots, required this.folders});

  final List<LibraryFolder> roots;
  final LibraryFolders folders;

  @override
  State<MoveTargetPage> createState() => _MoveTargetPageState();
}

class _Level {
  _Level(this.target, this.title, this.subfolders);

  final MoveTarget target;
  final String title;
  final Future<List<PlatformFolderEntry>> subfolders;
}

class _MoveTargetPageState extends State<MoveTargetPage> {
  final _levels = <_Level>[];

  void _enter(MoveTarget target, String title) {
    final subfolders = widget.folders
        .listFolder(target.treeUri, documentId: target.documentId)
        .then(
          (entries) =>
              sortEntries(entries.where((e) => e.isDirectory), FolderSort.name),
        );
    setState(() => _levels.add(_Level(target, title, subfolders)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final level = _levels.isEmpty ? null : _levels.last;
    return PopScope<MoveTarget>(
      canPop: _levels.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_levels.removeLast);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(level?.title ?? l10n.moveDocumentTitle),
          // Leaves the picker from any level.
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.x),
              tooltip: l10n.cancel,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: level == null ? _roots() : _subfolders(l10n, level),
        bottomNavigationBar: level == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    icon: const Icon(LucideIcons.folderSymlink),
                    label: Text(l10n.moveHere),
                    onPressed: () => Navigator.of(context).pop(level.target),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _roots() => ListView(
    children: [
      for (final root in widget.roots)
        ListTile(
          leading: const Icon(LucideIcons.folder),
          title: Text(root.displayName),
          onTap: () => _enter((
            treeUri: root.treeUri,
            documentId: null,
          ), root.displayName),
        ),
    ],
  );

  Widget _subfolders(AppLocalizations l10n, _Level level) =>
      FutureBuilder<List<PlatformFolderEntry>>(
        // A key per level, so a new level never shows the last one's list.
        key: ObjectKey(level),
        future: level.subfolders,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Note(l10n.folderUnreadable);
          }
          final entries = snapshot.data;
          if (entries == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (entries.isEmpty) return _Note(l10n.moveNoSubfolders);
          return ListView(
            children: [
              for (final folder in entries)
                ListTile(
                  leading: const Icon(LucideIcons.folder),
                  title: Text(folder.name),
                  onTap: () => _enter((
                    treeUri: level.target.treeUri,
                    documentId: folder.documentId,
                  ), folder.name),
                ),
            ],
          );
        },
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge,
    ),
  );
}

/// The file actions a document's menu offers (FR-FILE-011).
enum FileAction { rename, move, delete }

/// Menu entries for the file actions [actions] allows on [uri].
List<PopupMenuEntry<T>> fileActionItems<T>(
  AppLocalizations l10n,
  DocumentActions? actions,
  String? uri,
  T Function(FileAction action) value,
) {
  if (actions == null || !actions.canChange(uri)) return const [];
  return [
    PopupMenuItem(
      value: value(FileAction.rename),
      child: Text(l10n.renameDocument),
    ),
    if (actions.canMove(uri))
      PopupMenuItem(
        value: value(FileAction.move),
        child: Text(l10n.moveDocument),
      ),
    PopupMenuItem(
      value: value(FileAction.delete),
      child: Text(l10n.deleteDocument),
    ),
  ];
}

/// Runs [action] on the document at [uri] called [name]; true when the
/// file changed.
Future<bool> runFileAction(
  BuildContext context,
  DocumentActions actions,
  FileAction action, {
  required String uri,
  required String name,
}) => switch (action) {
  FileAction.rename => actions.rename(context, uri: uri, name: name),
  FileAction.move => actions.move(context, uri: uri),
  FileAction.delete => actions.delete(context, uri: uri, name: name),
};

sealed class _DocumentAction {
  const _DocumentAction();
}

class _ToggleFavorite extends _DocumentAction {
  const _ToggleFavorite();
}

class _RemoveFromRecents extends _DocumentAction {
  const _RemoveFromRecents();
}

class _OnFile extends _DocumentAction {
  const _OnFile(this.action);

  final FileAction action;
}

/// Trailing actions shared by the dashboard and the full document lists.
class DocumentRowActions extends StatelessWidget {
  const DocumentRowActions({
    super.key,
    required this.document,
    required this.library,
    required this.actions,
    required this.showRemoveFromRecents,
    this.foregroundColor,
  });

  final LibraryDocument document;
  final LibraryRepository? library;
  final DocumentActions? actions;
  final bool showRemoveFromRecents;
  final Color? foregroundColor;

  void _select(BuildContext context, _DocumentAction action) {
    switch (action) {
      case _ToggleFavorite():
        unawaited(library?.setFavorite(document.id, !document.favorite));
      case _RemoveFromRecents():
        unawaited(library?.removeFromRecents(document.id));
      case _OnFile(:final action):
        unawaited(
          runFileAction(
            context,
            actions!,
            action,
            uri: document.uri!,
            name: document.displayName,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fileItems = fileActionItems<_DocumentAction>(
      l10n,
      actions,
      document.uri,
      _OnFile.new,
    );
    final favorite = document.favorite;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FavoriteButton(
          favorite: favorite,
          foregroundColor: foregroundColor,
          onPressed: library == null
              ? null
              : () => unawaited(library!.setFavorite(document.id, !favorite)),
        ),
        if (showRemoveFromRecents || fileItems.isNotEmpty)
          PopupMenuButton<_DocumentAction>(
            iconColor: foregroundColor,
            onSelected: (action) => _select(context, action),
            itemBuilder: (_) => [
              if (showRemoveFromRecents) ...[
                PopupMenuItem(
                  value: const _ToggleFavorite(),
                  child: Text(favoriteLabel(l10n, favorite)),
                ),
                PopupMenuItem(
                  value: const _RemoveFromRecents(),
                  child: Text(l10n.removeFromRecents),
                ),
              ],
              ...fileItems,
            ],
          ),
      ],
    );
  }
}
