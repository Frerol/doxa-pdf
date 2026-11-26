// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'dictionary_library.dart';

/// Why a staged StarDict set was not installed.
typedef ImportProblem = ({String set, String? missingFile});

/// What installing a staging folder did (FR-TEXT-009).
typedef InstallReport = ({
  List<String> added,
  List<String> duplicates,
  List<ImportProblem> problems,
});

/// Installs the StarDict sets found anywhere under [staging] into [root],
/// one folder each, and deletes [staging]. A set is skipped, and reported,
/// when a companion file is missing (named), when it does not validate, or
/// when the same set is already installed. Runs synchronously: call it on
/// another isolate.
InstallReport installStaged(String root, String staging) {
  final added = <String>[];
  final duplicates = <String>[];
  final problems = <ImportProblem>[];
  final stagingDir = Directory(staging);
  try {
    final ifos =
        stagingDir
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where(
              (f) => f.path.endsWith('.ifo') && !_name(f.path).startsWith('.'),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final installed = _installedInfos(Directory(root));
    for (final ifo in ifos) {
      final base = ifo.path.substring(0, ifo.path.length - '.ifo'.length);
      final label = _name(ifo.path);
      final missing = [
        if (!_exists('$base.idx') && !_exists('$base.idx.gz')) '.idx',
        if (!_exists('$base.dict') && !_exists('$base.dict.dz')) '.dict',
      ];
      if (missing.isNotEmpty) {
        problems.add((
          set: label,
          missingFile: '${_name(base)}${missing.first}',
        ));
        continue;
      }
      final String name;
      try {
        // Opening validates the indexes and every definition range.
        final dictionary = Dictionary.open(ifo);
        name = dictionary.info.bookName;
        dictionary.close();
      } on DictionaryFormatException {
        problems.add((set: label, missingFile: null));
        continue;
      } on FileSystemException {
        problems.add((set: label, missingFile: null));
        continue;
      }
      final bytes = ifo.readAsStringSync();
      if (installed.contains(bytes)) {
        duplicates.add(name);
        continue;
      }
      final target = Directory('$root/${_freeId(root, name)}')
        ..createSync(recursive: true);
      final prefix = '${_name(base)}.';
      for (final file
          in ifo.parent.listSync(followLinks: false).whereType<File>()) {
        final fileName = _name(file.path);
        if (!fileName.endsWith('.fold') &&
            (fileName.startsWith(prefix) || _isNote(fileName))) {
          _move(file, '${target.path}/$fileName');
        }
      }
      try {
        // The install itself runs on a short-lived isolate.
        Dictionary.buildFoldIndex('${target.path}/$label');
      } on FileSystemException {
        // The worker can retry if the derived file could not be written.
      } on FormatException {
        // Exact lookup remains available for sets beyond the sidecar limits.
      }
      installed.add(bytes);
      added.add(name);
    }
  } finally {
    if (stagingDir.existsSync()) stagingDir.deleteSync(recursive: true);
  }
  return (added: added, duplicates: duplicates, problems: problems);
}

String _name(String path) => path.substring(path.lastIndexOf('/') + 1);

bool _exists(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) ==
    FileSystemEntityType.file;

bool _isNote(String name) {
  final lower = name.toLowerCase();
  return lower.startsWith('license') ||
      lower.startsWith('licence') ||
      lower.startsWith('readme') ||
      lower.startsWith('copying');
}

/// The `.ifo` texts already installed, to spot a set imported twice.
Set<String> _installedInfos(Directory root) => {
  if (root.existsSync())
    for (final file in root.listSync(recursive: true, followLinks: false))
      if (file is File && file.path.endsWith('.ifo')) file.readAsStringSync(),
};

/// A folder name for [bookName] under [root]: lowercase ASCII letters and
/// digits joined by dashes, with a number added when it is taken.
String _freeId(String root, String bookName) {
  var slug = bookName
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > 40) slug = slug.substring(0, 40);
  if (slug.isEmpty) slug = 'dictionary';
  var id = slug;
  for (
    var n = 2;
    FileSystemEntity.typeSync('$root/$id') != FileSystemEntityType.notFound;
    n++
  ) {
    id = '$slug-$n';
  }
  return id;
}

/// Moves [file]; the staging folder may be on another file system.
void _move(File file, String to) {
  try {
    file.renameSync(to);
  } on FileSystemException {
    file.copySync(to);
    file.deleteSync();
  }
}

/// Imports dictionaries from the system picker or from "Open with"
/// (FR-TEXT-009, FR-TEXT-012), and tells the user what happened.
final class DictionaryImporter {
  DictionaryImporter({required this.library, required this.imports});

  final DictionaryLibrary library;
  final DictionaryImports imports;

  /// Imports a `.zip` or loose files picked by the user.
  Future<void> pickFiles(BuildContext context) =>
      _run(context, imports.pickFiles);

  /// Imports the dictionaries of a folder picked by the user.
  Future<void> pickFolder(BuildContext context) =>
      _run(context, imports.pickFolder);

  /// Imports every waiting `.zip` opened with "Open with".
  Future<void> takeIncoming(BuildContext context) async {
    while (context.mounted) {
      var staged = false;
      await _run(context, () async {
        final path = await imports.takeIncoming();
        staged = path != null;
        return path;
      });
      if (!staged) return;
    }
  }

  Future<void> _run(
    BuildContext context,
    Future<String?> Function() stage,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    void show(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    final String? staging;
    try {
      staging = await stage();
    } on DictionaryImportException catch (error) {
      show(switch (error.error) {
        DictionaryImportError.tooLarge => l10n.dictionaryTooLarge,
        DictionaryImportError.notDictionary => l10n.dictionaryNotZip,
        DictionaryImportError.missing => l10n.fileMissing,
        DictionaryImportError.permissionLost => l10n.filePermissionLost,
        DictionaryImportError.unreadable => l10n.fileUnreadable,
      });
      return;
    }
    if (staging == null) return;
    final InstallReport report;
    try {
      report = await library.install(staging);
    } on Object catch (error) {
      debugPrint('Doxa: cannot install dictionary: $error');
      show(l10n.fileUnreadable);
      return;
    }
    show(importMessage(l10n, report));
  }
}

/// One line about [report]: what was added, then the first problem.
String importMessage(AppLocalizations l10n, InstallReport report) {
  final (:added, :duplicates, :problems) = report;
  final parts = <String>[
    if (added.length == 1) l10n.dictionaryAdded(added.single),
    if (added.length > 1) l10n.dictionaryAddedCount(added.length),
    if (added.isEmpty && duplicates.isNotEmpty)
      l10n.dictionaryAlreadyInstalled(duplicates.first),
    if (problems.isNotEmpty)
      switch (problems.first) {
        (set: _, missingFile: final String file) => l10n.dictionaryMissingFile(
          file,
        ),
        (set: final set, missingFile: null) => l10n.dictionaryInvalid(set),
      },
  ];
  return parts.isEmpty ? l10n.dictionaryNoneFound : parts.join(' ');
}

/// Imports "Open with" `.zip` files while the app runs (FR-TEXT-012),
/// including one that started the app.
class IncomingDictionaries extends StatefulWidget {
  const IncomingDictionaries({
    super.key,
    required this.importer,
    required this.child,
  });

  final DictionaryImporter importer;
  final Widget child;

  @override
  State<IncomingDictionaries> createState() => _IncomingDictionariesState();
}

class _IncomingDictionariesState extends State<IncomingDictionaries> {
  StreamSubscription<void>? _signals;
  bool _draining = false;

  @override
  void initState() {
    super.initState();
    _signals = widget.importer.imports.incoming.listen((_) => _drain());
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
  }

  @override
  void dispose() {
    unawaited(_signals?.cancel());
    super.dispose();
  }

  Future<void> _drain() async {
    if (_draining || !mounted) return;
    _draining = true;
    try {
      await widget.importer.takeIncoming(context);
    } finally {
      _draining = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
