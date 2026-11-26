// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:doxa_pdf/features/dictionary/dictionaries_page.dart';
import 'package:doxa_pdf/features/dictionary/dictionary_library.dart';
import 'package:doxa_pdf/features/dictionary/dictionary_popup.dart';
import 'package:doxa_pdf/l10n/gen/app_localizations.dart';
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
      var imported = 0;
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
          onImport: () => imported++,
        ),
      );
      await tester.tap(find.text('Get dictionaries'));
      await tester.tap(find.text('Import file'));
      expect(opened, [dictionariesPage]);
      expect(imported, 1);
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
