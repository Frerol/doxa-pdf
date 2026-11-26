// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:material_ui/material_ui.dart';

import 'dictionary_import.dart';

/// A dictionary the user installed (FR-TEXT-009): one folder under the
/// library's root holding a StarDict set.
@immutable
final class InstalledDictionary {
  const InstalledDictionary({
    required this.id,
    required this.name,
    required this.ifoPath,
    required this.enabled,
    required this.sizeBytes,
    this.description = '',
    this.website,
  });

  /// The folder's name under the library root.
  final String id;

  /// The `.ifo` bookname.
  final String name;
  final String ifoPath;
  final bool enabled;

  /// Bytes on disk, for the settings list.
  final int sizeBytes;
  final String description;
  final String? website;

  InstalledDictionary copyWith({bool? enabled}) => InstalledDictionary(
    id: id,
    name: name,
    ifoPath: ifoPath,
    enabled: enabled ?? this.enabled,
    sizeBytes: sizeBytes,
    description: description,
    website: website,
  );
}

/// The installed dictionaries in the user's order (FR-TEXT-009): which are
/// enabled, their order, and removing them. The order and the enabled
/// state are kept in `dictionaries.json` next to the folders.
final class DictionaryLibrary extends ChangeNotifier {
  DictionaryLibrary(String root) : root = Directory(root);

  final Directory root;
  List<InstalledDictionary> _all = const [];
  bool _loaded = false;

  List<InstalledDictionary> get all => _all;
  List<InstalledDictionary> get enabled => [
    for (final d in _all)
      if (d.enabled) d,
  ];
  bool get loaded => _loaded;

  File get _manifest => File('${root.path}/dictionaries.json');

  /// Finds the installed sets. Validating a large set reads its index, so
  /// this runs on another isolate.
  Future<void> load() async {
    final found = await _scanOnIsolate(root.path);
    final saved = await _readManifest();
    final byId = {for (final d in found) d.id: d};
    _all = [
      for (final entry in saved)
        if (byId.remove(entry.id) case final d?) d.copyWith(enabled: entry.on),
      // Dictionaries the manifest does not know yet come last, enabled.
      ...byId.values,
    ];
    _loaded = true;
    notifyListeners();
  }

  Future<List<({String id, bool on})>> _readManifest() async {
    try {
      final json = jsonDecode(await _manifest.readAsString());
      return [
        for (final item in (json as List).cast<Map<String, Object?>>())
          (id: item['id']! as String, on: item['enabled']! as bool),
      ];
    } on Object {
      // Missing or damaged: every dictionary found is listed, enabled.
      return const [];
    }
  }

  Future<void> _save() async {
    await root.create(recursive: true);
    final temp = File('${_manifest.path}.tmp');
    await temp.writeAsString(
      jsonEncode([
        for (final d in _all) {'id': d.id, 'enabled': d.enabled},
      ]),
      flush: true,
    );
    await temp.rename(_manifest.path);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    _all = [
      for (final d in _all) d.id == id ? d.copyWith(enabled: enabled) : d,
    ];
    notifyListeners();
    await _save();
  }

  /// Moves the dictionary at [from] so it ends up at [to].
  Future<void> move(int from, int to) async {
    if (from == to) return;
    final list = [..._all];
    list.insert(to, list.removeAt(from));
    _all = list;
    notifyListeners();
    await _save();
  }

  /// Installs the sets staged in [staging] (see `installStaged`), on
  /// another isolate, and lists them, enabled, after the others.
  Future<InstallReport> install(String staging) async {
    final report = await _installOnIsolate(root.path, staging);
    await load();
    return report;
  }

  /// Deletes the dictionary's folder.
  Future<void> remove(String id) async {
    _all = [
      for (final d in _all)
        if (d.id != id) d,
    ];
    notifyListeners();
    await _save();
    final folder = Directory('${root.path}/$id');
    if (await folder.exists()) await folder.delete(recursive: true);
  }
}

// Top-level, so the closures capture only their plain arguments: a
// closure made in a method can capture `this` and its zone, which cannot
// be sent to another isolate.
Future<List<InstalledDictionary>> _scanOnIsolate(String root) =>
    Isolate.run(() => _scan(root));

Future<InstallReport> _installOnIsolate(String root, String staging) =>
    Isolate.run(() => installStaged(root, staging));

List<InstalledDictionary> _scan(String rootPath) {
  final root = Directory(rootPath);
  if (!root.existsSync()) return const [];
  final found = <InstalledDictionary>[];
  final folders =
      root.listSync(followLinks: false).whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final folder in folders) {
    final sets = Dictionary.findAll(folder).valid;
    // One set per folder: an import puts each set in its own folder.
    if (sets.isEmpty) continue;
    final (:ifo, :info) = sets.first;
    var size = 0;
    for (final file in folder.listSync(recursive: true, followLinks: false)) {
      if (file is File) size += file.lengthSync();
    }
    found.add(
      InstalledDictionary(
        id: folder.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
        name: info.bookName,
        ifoPath: ifo.path,
        enabled: true,
        sizeBytes: size,
        description: info.description ?? '',
        website: info.website,
      ),
    );
  }
  return found;
}

/// Makes the dictionaries reachable from the reader and the settings.
class DictionaryScope extends InheritedWidget {
  const DictionaryScope({
    super.key,
    required this.library,
    required this.lookup,
    required this.openUri,
    this.importer,
    required super.child,
  });

  final DictionaryLibrary library;
  final DictionaryLookup lookup;

  /// Opens the dictionaries page in the browser.
  final Future<bool> Function(String uri) openUri;

  /// Imports dictionaries; Import file is hidden when null.
  final DictionaryImporter? importer;

  static DictionaryScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DictionaryScope>();

  @override
  bool updateShouldNotify(DictionaryScope old) =>
      library != old.library ||
      lookup != old.lookup ||
      importer != old.importer;
}

/// The entries or read failure for one dictionary.
typedef LookupGroup = ({
  String dictionary,
  List<({String headword, DefinitionResult definition})> entries,
  bool failed,
});

/// The entries and alternate headwords returned by one lookup request.
final class LookupResult {
  const LookupResult(
    this.groups, {
    this.suggestions = const [],
    this.shownWord,
  });

  final List<LookupGroup> groups;
  final List<String> suggestions;

  /// The suggestion opened automatically for a query that missed everywhere.
  final String? shownWord;
}

/// Looks words up in a long-lived isolate (ADR-0009: never on the UI
/// isolate, never on the engine's), which keeps the dictionaries open
/// between lookups.
abstract interface class DictionaryLookup {
  /// The results of [query] in [dictionaries], in that order.
  Future<LookupResult> lookup(
    String query,
    List<InstalledDictionary> dictionaries,
  );

  Future<void> close();
}

/// [DictionaryLookup] on a worker isolate.
final class IsolateDictionaryLookup implements DictionaryLookup {
  Future<SendPort>? _worker;
  Isolate? _isolate;

  Future<SendPort> _start() => _worker ??= () async {
    final ready = ReceivePort();
    _isolate = await Isolate.spawn(_workerMain, ready.sendPort);
    final port = await ready.first as SendPort;
    ready.close();
    return port;
  }();

  @override
  Future<LookupResult> lookup(
    String query,
    List<InstalledDictionary> dictionaries,
  ) async {
    final worker = await _start();
    final reply = ReceivePort();
    worker.send((
      reply.sendPort,
      query,
      [for (final d in dictionaries) (name: d.name, ifo: d.ifoPath)],
    ));
    final result = await reply.first;
    reply.close();
    return result as LookupResult;
  }

  @override
  Future<void> close() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _worker = null;
  }
}

void _workerMain(SendPort ready) {
  final requests = ReceivePort();
  ready.send(requests.sendPort);
  final open = <String, Dictionary>{};
  requests.listen((message) {
    final (
      SendPort reply,
      String query,
      List<({String name, String ifo})> wanted,
    ) = message as (SendPort, String, List<({String name, String ifo})>);
    // Dictionaries no longer wanted (disabled or removed) are closed.
    final paths = {for (final d in wanted) d.ifo};
    for (final path in open.keys.where((p) => !paths.contains(p)).toList()) {
      open.remove(path)!.close();
    }
    List<LookupGroup> readEntries(String word) => [
      for (final (:name, :ifo) in wanted) _readEntries(open, ifo, name, word),
    ];

    final groups = readEntries(query);
    if (groups.any((group) => group.entries.isNotEmpty)) {
      reply.send(LookupResult(groups));
      return;
    }

    // Score the union of the existing per-dictionary suggestions before the
    // popup caps the chips. A tied distance leaves all suggestions as chips.
    final suggestions = <String>{};
    for (var i = 0; i < wanted.length; i++) {
      if (groups[i].failed) continue;
      try {
        suggestions.addAll(open[wanted[i].ifo]!.suggest(query, limit: 5));
      } on Object {
        groups[i] = (
          dictionary: groups[i].dictionary,
          entries: const [],
          failed: true,
        );
      }
    }
    final closest = closestSuggestion(query, suggestions);
    if (closest != null) {
      final matches = readEntries(closest);
      if (matches.any((group) => group.entries.isNotEmpty)) {
        suggestions.remove(closest);
        reply.send(
          LookupResult(
            matches,
            suggestions: suggestions.toList(),
            shownWord: closest,
          ),
        );
        return;
      }
    }
    reply.send(LookupResult(groups, suggestions: suggestions.toList()));
  });
}

LookupGroup _readEntries(
  Map<String, Dictionary> open,
  String ifo,
  String name,
  String query,
) {
  try {
    final dictionary = open[ifo] ??= Dictionary.open(File(ifo));
    return (
      dictionary: name,
      entries: [
        for (final e in dictionary.lookup(query))
          (headword: e.headword, definition: convertDefinition(e.fields)),
      ],
      failed: false,
    );
  } on Object {
    // A damaged file must not take the other dictionaries down.
    return (dictionary: name, entries: const [], failed: true);
  }
}
