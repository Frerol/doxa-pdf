// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:doxa_pdf/features/dictionary/dictionaries_page.dart';
import 'package:doxa_pdf/features/dictionary/dictionary_import.dart';
import 'package:doxa_pdf/features/dictionary/dictionary_library.dart';
import 'package:doxa_pdf/features/dictionary/dictionary_popup.dart';
import 'package:doxa_pdf/l10n/gen/app_localizations.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Writes a plain StarDict set with [entries] (lowercase ASCII headwords,
/// so sorting them is StarDict's order) into [folder].
void writeSet(Directory folder, String name, Map<String, String> entries) {
  folder.createSync(recursive: true);
  final words = entries.keys.toList()..sort();
  final idx = BytesBuilder();
  final dict = BytesBuilder();
  for (final word in words) {
    final definition = utf8.encode(entries[word]!);
    idx
      ..add(utf8.encode(word))
      ..addByte(0)
      ..add(
        (ByteData(8)
              ..setUint32(0, dict.length)
              ..setUint32(4, definition.length))
            .buffer
            .asUint8List(),
      );
    dict.add(definition);
  }
  final index = idx.takeBytes();
  File('${folder.path}/$name.idx').writeAsBytesSync(index);
  File('${folder.path}/$name.dict').writeAsBytesSync(dict.takeBytes());
  File('${folder.path}/$name.ifo').writeAsStringSync(
    "StarDict's dict ifo file\nversion=3.0.0\nbookname=$name\n"
    'wordcount=${words.length}\nidxfilesize=${index.length}\n'
    'sametypesequence=m\ndescription=Sample $name\n',
  );
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('doxa-dict-'));
  tearDown(() => root.deleteSync(recursive: true));

  group('dictionary library (FR-TEXT-009)', () {
    test('keeps order and enabled state, and lists new sets last', () async {
      writeSet(Directory('${root.path}/b'), 'Beta', {'cat': 'feline'});
      writeSet(Directory('${root.path}/a'), 'Alpha', {'cat': 'animal'});
      Directory('${root.path}/broken').createSync();
      final library = DictionaryLibrary(root.path);
      await library.load();
      expect(library.all.map((d) => d.name), ['Alpha', 'Beta']);

      await library.move(0, 1);
      await library.setEnabled('b', false);
      writeSet(Directory('${root.path}/c'), 'Gamma', {'dog': 'canine'});
      final again = DictionaryLibrary(root.path);
      await again.load();
      expect(again.all.map((d) => d.name), ['Beta', 'Alpha', 'Gamma']);
      expect(again.enabled.map((d) => d.name), ['Alpha', 'Gamma']);
      expect(again.all.first.description, 'Sample Beta');
      expect(again.all.first.sizeBytes, greaterThan(0));
    });

    test('removing a dictionary deletes its folder', () async {
      writeSet(Directory('${root.path}/a'), 'Alpha', {'cat': 'animal'});
      final library = DictionaryLibrary(root.path);
      await library.load();
      await library.remove('a');
      expect(library.all, isEmpty);
      expect(Directory('${root.path}/a').existsSync(), isFalse);
    });
  });

  group('import (FR-TEXT-009)', () {
    late String installed;
    late Directory staging;
    setUp(() {
      installed = '${root.path}/installed';
      staging = Directory('${root.path}/staging')..createSync();
    });

    test('installs sets from nested folders, one folder each', () {
      writeSet(Directory('${staging.path}/a/b'), 'Alpha Pack', {'cat': 'x'});
      writeSet(staging, 'beta', {'dog': 'y'});
      File('${staging.path}/LICENSE.txt').writeAsStringSync('CC BY-SA');
      final report = installStaged(installed, staging.path);
      expect(report.added, ['Alpha Pack', 'beta']);
      expect(report.problems, isEmpty);
      expect(staging.existsSync(), isFalse);
      expect(File('$installed/alpha-pack/Alpha Pack.ifo').existsSync(), isTrue);
      expect(File('$installed/beta/LICENSE.txt').existsSync(), isTrue);
    });

    test('names a missing file, rejects a bad set, skips a duplicate', () {
      writeSet(Directory('${staging.path}/ok'), 'Alpha', {'cat': 'x'});
      installStaged(installed, staging.path);

      staging.createSync();
      writeSet(Directory('${staging.path}/again'), 'Alpha', {'cat': 'x'});
      writeSet(Directory('${staging.path}/nodict'), 'Gamma', {'cat': 'x'});
      File('${staging.path}/nodict/Gamma.dict').deleteSync();
      writeSet(Directory('${staging.path}/bad'), 'Delta', {'cat': 'x'});
      File('${staging.path}/bad/Delta.idx').writeAsBytesSync([1, 2, 3]);
      final report = installStaged(installed, staging.path);
      expect(report.added, isEmpty);
      expect(report.duplicates, ['Alpha']);
      expect(report.problems, [
        (set: 'Delta.ifo', missingFile: null),
        (set: 'Gamma.ifo', missingFile: 'Gamma.dict'),
      ]);
      expect(Directory(installed).listSync(), hasLength(1));
    });

    test('the message says what was added, then the first problem', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        importMessage(l10n, (
          added: ['Alpha'],
          duplicates: const [],
          problems: [(set: 'Gamma.ifo', missingFile: 'Gamma.dict')],
        )),
        'Added “Alpha”. “Gamma.dict” is missing.',
      );
      expect(
        importMessage(l10n, (
          added: const [],
          duplicates: const [],
          problems: const [],
        )),
        startsWith('No dictionary found.'),
      );
    });

    testWidgets('a .zip opened with Open with is imported at start', (
      tester,
    ) async {
      final library = DictionaryLibrary(installed);
      writeSet(staging, 'Alpha', {'cat': 'x'});
      final imports = _FakeImports()..incomingStaged.add(staging.path);
      tester.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => IncomingDictionaries(
            importer: DictionaryImporter(library: library, imports: imports),
            child: child!,
          ),
          home: const Scaffold(),
        ),
      );
      for (
        var i = 0;
        i < 50 && find.text('Added “Alpha”.').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(library.all.single.name, 'Alpha');
      expect(find.text('Added “Alpha”.'), findsOneWidget);
    });
  });

  group('lookup (FR-TEXT-008, FR-TEXT-010)', () {
    test('runs on a worker, in the given order, past a damaged set', () async {
      writeSet(Directory('${root.path}/a'), 'Alpha', {'cat': 'animal'});
      writeSet(Directory('${root.path}/b'), 'Beta', {
        'cat': 'feline',
        'car': 'auto',
      });
      final library = DictionaryLibrary(root.path);
      await library.load();
      final lookup = IsolateDictionaryLookup();
      addTearDown(lookup.close);
      final [alpha, beta] = library.all;

      final groups = await lookup.lookup('Cat.', [beta, alpha]);
      expect(groups.map((g) => g.dictionary), ['Beta', 'Alpha']);
      expect(groups.first.entries.single.headword, 'cat');
      expect(lookupText(groups), contains('feline'));

      final missing = await lookup.lookup('cas', [beta]);
      expect(missing.single.entries, isEmpty);
      expect(missing.single.suggestions, containsAll(['car', 'cat']));

      File('${root.path}/a/Alpha.idx').writeAsBytesSync([1, 2, 3]);
      final damaged = InstalledDictionary(
        id: 'x',
        name: 'Damaged',
        ifoPath: '${root.path}/a/Alpha.ifo',
        enabled: true,
        sizeBytes: 0,
      );
      final mixed = await lookup.lookup('cat', [damaged, beta]);
      expect(mixed.first.failed, isTrue);
      expect(mixed.last.entries.single.headword, 'cat');
    });
  });

  group('lookup popup (FR-TEXT-008, FR-TEXT-012)', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('with no dictionary it explains how to get one', (
      tester,
    ) async {
      final opened = <String>[];
      await pump(
        tester,
        DictionaryLookupView(
          query: 'cat',
          library: DictionaryLibrary(root.path),
          lookup: _FakeLookup(),
          openUri: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      );
      await tester.tap(find.text('Get dictionaries'));
      expect(opened, [dictionariesPage]);
      // Without an importer there is nothing to import with.
      expect(find.text('Import file'), findsNothing);
    });

    testWidgets('Import file from the empty state answers the lookup', (
      tester,
    ) async {
      final library = DictionaryLibrary('${root.path}/installed');
      final staging = Directory('${root.path}/staging');
      writeSet(Directory('${staging.path}/pack/nested'), 'Alpha', {
        'cat': 'animal',
      });
      final imports = _FakeImports()..staged.add(staging.path);
      final lookup = _FakeLookup();
      await pump(
        tester,
        DictionaryLookupView(
          query: 'cat',
          library: library,
          lookup: lookup,
          openUri: (_) async => true,
          importer: DictionaryImporter(library: library, imports: imports),
        ),
      );
      await tester.tap(find.text('Import file'));
      // Staging, installing and finding the set use real isolates and I/O.
      for (
        var i = 0;
        i < 50 && find.text('Added “Alpha”.').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Added “Alpha”.'), findsOneWidget);
      expect(lookup.queries, ['cat']);
      expect(find.textContaining('feline animal'), findsOneWidget);
    });

    testWidgets('groups results by dictionary and follows suggestions', (
      tester,
    ) async {
      writeSet(Directory('${root.path}/a'), 'Alpha', {'cat': 'animal'});
      final library = DictionaryLibrary(root.path);
      await tester.runAsync(library.load);
      final lookup = _FakeLookup();
      await pump(
        tester,
        DictionaryLookupView(
          query: 'cas',
          library: library,
          lookup: lookup,
          openUri: (_) async => true,
        ),
      );
      expect(find.text('No entry for “cas”.'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'cat'));
      await tester.pumpAndSettle();
      expect(lookup.queries, ['cas', 'cat']);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.textContaining('feline animal'), findsOneWidget);
    });
  });

  for (final hasDictionaries in [false, true]) {
    testWidgets('settings offers both import actions from the app bar and body '
        '(has dictionaries: $hasDictionaries, FR-TEXT-009)', (tester) async {
      if (hasDictionaries) {
        writeSet(Directory('${root.path}/a'), 'Alpha', {'cat': 'animal'});
      }
      final library = DictionaryLibrary(root.path);
      await tester.runAsync(library.load);
      final imports = _FakeImports();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: DictionariesPage(
            library: library,
            openUri: (_) async => true,
            importer: DictionaryImporter(library: library, imports: imports),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(hasDictionaries ? 'Alpha' : 'No dictionary yet'),
        findsOneWidget,
      );

      for (final (label, picker) in [
        ('Import file', 'files'),
        ('Import folder', 'folder'),
      ]) {
        final toolbarAction = find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip(label),
        );
        final bodyAction = find.widgetWithText(OutlinedButton, label);
        for (final action in [toolbarAction, bodyAction]) {
          expect(action.hitTestable(), findsOneWidget);
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(imports.pickerCalls, [picker]);
          imports.pickerCalls.clear();
        }
      }
    });
  }

  testWidgets('settings list, disable and remove dictionaries (FR-TEXT-009)', (
    tester,
  ) async {
    writeSet(Directory('${root.path}/a'), 'Alpha', {'cat': 'animal'});
    final library = DictionaryLibrary(root.path);
    await tester.runAsync(library.load);
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: DictionariesPage(library: library, openUri: (_) async => true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Sample Alpha'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byType(Switch));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(library.enabled, isEmpty);

    await tester.tap(find.byTooltip('Remove Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    // The manifest is saved and the files deleted with real I/O, one step
    // after another.
    for (var i = 0; i < 20 && Directory('${root.path}/a').existsSync(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('No dictionary yet'), findsOneWidget);
    expect(Directory('${root.path}/a').existsSync(), isFalse);
  });
}

class _FakeImports implements DictionaryImports {
  final staged = <String>[];
  final incomingStaged = <String>[];
  final pickerCalls = <String>[];

  @override
  Future<String?> pickFiles() async {
    pickerCalls.add('files');
    return staged.isEmpty ? null : staged.removeAt(0);
  }

  @override
  Future<String?> pickFolder() async {
    pickerCalls.add('folder');
    return staged.isEmpty ? null : staged.removeAt(0);
  }

  @override
  Stream<void> get incoming => const Stream.empty();

  @override
  Future<String?> takeIncoming() async =>
      incomingStaged.isEmpty ? null : incomingStaged.removeAt(0);
}

class _FakeLookup implements DictionaryLookup {
  final queries = <String>[];

  @override
  Future<List<LookupGroup>> lookup(
    String query,
    List<InstalledDictionary> dictionaries,
  ) async {
    queries.add(query);
    final hit = query == 'cat';
    return [
      for (final d in dictionaries)
        (
          dictionary: d.name,
          entries: hit
              ? [
                  (
                    headword: 'cat',
                    definition: DefinitionResult([
                      DefinitionBlock(DefinitionBlockKind.paragraph, const [
                        DefinitionSpan('feline animal'),
                      ]),
                    ], unsupportedFields: 0),
                  ),
                ]
              : const <({String headword, DefinitionResult definition})>[],
          suggestions: hit ? const <String>[] : const ['cat'],
          failed: false,
        ),
    ];
  }

  @override
  Future<void> close() async {}
}
