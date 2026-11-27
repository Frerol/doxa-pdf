// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:doxa_pdf/features/dictionary/dictionaries_page.dart';
import 'package:doxa_pdf/features/dictionary/dictionary_catalog.dart';
import 'package:doxa_pdf/features/dictionary/dictionary_downloads.dart';
import 'package:doxa_pdf/features/dictionary/dictionary_import.dart';
import 'package:doxa_pdf/features/dictionary/dictionary_library.dart';
import 'package:doxa_pdf/l10n/gen/app_localizations.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'dictionary_test.dart' show writeSet;

void main() {
  late Directory temp;
  late Directory cache;
  late Directory sources;
  late DictionaryLibrary library;
  late _FakeConditions conditions;
  late _FakeDownloader downloader;
  late _FakeImports imports;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('doxa-downloads-');
    cache = Directory('${temp.path}/cache')..createSync();
    sources = Directory('${temp.path}/sources')..createSync();
    library = DictionaryLibrary('${temp.path}/dictionaries');
    conditions = _FakeConditions(cache.path);
    downloader = _FakeDownloader();
    imports = _FakeImports(sources.path);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  /// A pack whose download stages the set [bookName] with [entries].
  Future<CatalogPack> pack(
    String id,
    String bookName, [
    Map<String, String> entries = const {'cat': 'feline'},
  ]) async {
    final folder = Directory('${sources.path}/$id');
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    writeSet(folder, bookName, entries);
    return CatalogPack(
      id: id,
      name: 'Pack $id',
      language: 'en',
      bookName: bookName,
      url: Uri.parse('https://example.org/$id.zip'),
      sha256: '0' * 64,
      sizeBytes: 10,
      unpackedBytes: 10,
      ifoSha256: await fileSha256(File('${folder.path}/$bookName.ifo')),
      source: 'Wiktionary',
      licence: 'CC BY-SA 4.0',
    );
  }

  DictionaryDownloads downloads() => DictionaryDownloads(
    library: library,
    imports: imports,
    conditions: conditions,
    downloader: downloader,
  );

  group('pack downloads (ADR-0010)', () {
    test('a downloaded pack is installed, enabled, and leaves no files '
        'behind', () async {
      await library.load();
      final alpha = await pack('alpha', 'Alpha');
      downloader.packs = [alpha];
      final controller = downloads();
      await controller.refresh();
      expect(controller.statusOf(alpha), PackStatus.available);

      final outcome = await controller.install(alpha);
      expect(outcome, isA<PackInstalled>());
      expect(library.enabled.map((d) => d.name), ['Alpha']);
      expect(controller.statusOf(alpha), PackStatus.installed);
      expect(cache.listSync(), isEmpty);
      expect(controller.active, isNull);
    });

    test('a pack that does not fit is not downloaded', () async {
      await library.load();
      final alpha = await pack('alpha', 'Alpha');
      conditions.free = 19;
      final outcome = await downloads().install(alpha);
      expect(outcome, isA<PackNoSpace>());
      expect((outcome as PackNoSpace).neededBytes, 20);
      expect(downloader.downloads, isEmpty);
    });

    test('a failed download installs nothing', () async {
      await library.load();
      final alpha = await pack('alpha', 'Alpha');
      downloader.error = DownloadError.corrupt;
      final outcome = await downloads().install(alpha);
      expect(outcome, isA<PackFailed>());
      expect((outcome as PackFailed).error, DownloadError.corrupt);
      expect(library.all, isEmpty);
      expect(imports.staged, 0);
    });

    test('an update replaces the installed build in its place', () async {
      await library.load();
      final controller = downloads();
      final old = await pack('alpha', 'Alpha', {'cat': 'old'});
      await controller.install(old);
      await controller.install(await pack('beta', 'Beta'));
      expect(library.all.map((d) => d.name), ['Alpha', 'Beta']);

      final rebuilt = await pack('alpha', 'Alpha', {'cat': 'new', 'dog': 'x'});
      downloader.packs = [rebuilt];
      await controller.refresh();
      expect(controller.statusOf(rebuilt), PackStatus.updateAvailable);

      await controller.install(rebuilt);
      expect(library.all.map((d) => d.name), ['Alpha', 'Beta']);
      expect(controller.statusOf(rebuilt), PackStatus.installed);
      final ifo = File(library.all.first.ifoPath).readAsStringSync();
      expect(ifo, contains('wordcount=2'));
    });
  });

  group('Get dictionaries page (ADR-0010, UX §9)', () {
    /// Lets real file I/O (the cache clean-up, hashing) finish.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> pumpPage(
      WidgetTester tester,
      DictionaryDownloads controller,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => DictionaryScope(
            library: library,
            lookup: _NoLookup(),
            openUri: (_) async => fail('The browser must not open'),
            importer: DictionaryImporter(library: library, imports: imports),
            downloads: controller,
            child: child!,
          ),
          home: DictionariesPage(
            library: library,
            openUri: (_) async => fail('The browser must not open'),
            importer: DictionaryImporter(library: library, imports: imports),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens from the empty state and lists each pack with its '
        'size, source and licence', (tester) async {
      await tester.runAsync(library.load);
      final alpha = await tester.runAsync(() => pack('alpha', 'Alpha'));
      downloader.packs = [alpha!];
      await pumpPage(tester, downloads());
      expect(find.text('No dictionary yet'), findsOneWidget);

      await tester.tap(find.text('Get dictionaries'));
      await settle(tester);
      expect(find.text('Pack alpha'), findsOneWidget);
      expect(
        find.textContaining('10 B · Wiktionary · CC BY-SA 4.0'),
        findsOneWidget,
      );
      expect(find.byTooltip('Download Pack alpha'), findsOneWidget);
      expect(downloader.catalogFetches, 1);
    });

    testWidgets('asks before downloading on a metered connection', (
      tester,
    ) async {
      await tester.runAsync(library.load);
      final alpha = await tester.runAsync(() => pack('alpha', 'Alpha'));
      downloader
        ..packs = [alpha!]
        // The download itself is not under test here.
        ..error = DownloadError.cancelled;
      conditions.metered = true;
      await pumpPage(tester, downloads());
      await tester.tap(find.text('Get dictionaries'));
      await settle(tester);

      await tester.tap(find.byTooltip('Download Pack alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Use mobile data?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(downloader.downloads, isEmpty);

      await tester.tap(find.byTooltip('Download Pack alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Download'));
      await tester.pumpAndSettle();
      expect(downloader.downloads, ['alpha']);
    });

    testWidgets('without a network it says so and keeps the import actions', (
      tester,
    ) async {
      await tester.runAsync(library.load);
      downloader.catalogError = DownloadError.offline;
      await pumpPage(tester, downloads());
      await tester.tap(find.text('Get dictionaries'));
      await settle(tester);
      expect(find.textContaining('No connection'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Import file'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Import folder'),
        findsOneWidget,
      );

      final alpha = await tester.runAsync(() => pack('alpha', 'Alpha'));
      downloader
        ..catalogError = null
        ..packs = [alpha!];
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('Pack alpha'), findsOneWidget);
    });
  });
}

class _FakeDownloader extends DictionaryDownloader {
  List<CatalogPack> packs = const [];
  DownloadError? catalogError;
  DownloadError? error;
  int catalogFetches = 0;
  final downloads = <String>[];

  @override
  Future<List<CatalogPack>> fetchCatalog(Uri uri) async {
    catalogFetches++;
    if (catalogError case final error?) throw DownloadException(error);
    return packs;
  }

  @override
  Future<File> download(
    CatalogPack pack,
    Directory directory, {
    void Function(int received)? onProgress,
    DownloadCancel? cancel,
  }) async {
    downloads.add(pack.id);
    if (error case final error?) throw DownloadException(error);
    onProgress?.call(pack.sizeBytes);
    final file = File('${directory.path}/${pack.id}.zip');
    await file.writeAsString(pack.id);
    return file;
  }
}

/// Stages the source folder named in the downloaded file.
class _FakeImports implements DictionaryImports {
  _FakeImports(this.sources);

  final String sources;
  int staged = 0;

  @override
  Future<String> stageArchive(String path) async {
    staged++;
    final id = await File(path).readAsString();
    final staging = Directory.systemTemp.createTempSync('doxa-staging-');
    for (final file in Directory('$sources/$id').listSync().whereType<File>()) {
      file.copySync('${staging.path}/${file.uri.pathSegments.last}');
    }
    return staging.path;
  }

  @override
  Future<String?> pickFiles() async => null;

  @override
  Future<String?> pickFolder() async => null;

  @override
  Stream<void> get incoming => const Stream.empty();

  @override
  Future<String?> takeIncoming() async => null;
}

class _FakeConditions implements DownloadConditions {
  _FakeConditions(this.cache);

  final String cache;
  bool metered = false;
  int? free;

  @override
  Future<String> cacheDirectory() async => cache;

  @override
  Future<int?> freeBytes() async => free;

  @override
  Future<bool> isMetered() async => metered;
}

class _NoLookup implements DictionaryLookup {
  @override
  Future<LookupResult> lookup(
    String query,
    List<InstalledDictionary> dictionaries,
  ) async => const LookupResult([]);

  @override
  Future<void> close() async {}
}
