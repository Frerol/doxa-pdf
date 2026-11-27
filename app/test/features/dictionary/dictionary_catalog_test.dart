// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:doxa_pdf/features/dictionary/dictionary_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// A catalogue entry for [bytes] served at [url].
Map<String, Object?> packJson(
  String id,
  List<int> bytes, {
  String url = 'pack.zip',
  String? sha,
}) => {
  'id': id,
  'name': 'Pack $id',
  'language': 'pt',
  'bookName': 'Book $id',
  'url': url,
  'sha256': sha ?? sha256.convert(bytes).toString(),
  'size': bytes.length,
  'unpackedSize': bytes.length * 2,
  'ifoSha256': sha256.convert(utf8.encode(id)).toString(),
  'source': 'Wiktionary',
  'licence': 'CC BY-SA 4.0',
};

void main() {
  group('catalogue (ADR-0010)', () {
    final base = Uri.parse('https://example.org/releases/v1/dictionaries.json');

    test('resolves pack addresses and keeps only the packs it understands', () {
      final good = packJson('pt', [1, 2, 3]);
      final packs = parseCatalog(
        jsonEncode({
          'format': 1,
          'packs': [
            good,
            {...good, 'id': 'tr', 'kind': 'translations'},
            {...good, 'id': 'http', 'url': 'http://example.org/a.zip'},
            {...good, 'id': 'nohash', 'sha256': 'abc'},
            {...good, 'id': 'nosize', 'size': 0},
            'not a pack',
            // A repeated id keeps the first entry.
            {...good, 'name': 'Second'},
          ],
        }),
        base,
      );
      expect(packs.map((p) => p.id), ['pt']);
      expect(
        packs.single.url,
        Uri.parse('https://example.org/releases/v1/pack.zip'),
      );
      expect(packs.single.name, 'Pack pt');
    });

    test('refuses an unknown format instead of guessing', () {
      for (final text in ['{"format": 2, "packs": []}', '[]', 'not json']) {
        expect(
          () => parseCatalog(text, base),
          throwsA(isA<CatalogFormatException>()),
        );
      }
    });

    test('the fixed address matches the app version', () {
      expect(catalogUri.scheme, 'https');
      expect(catalogUri.path, endsWith('/dictionaries.json'));
      expect(catalogUri.path, isNot(contains('+')));
      expect(catalogUri.query, isEmpty);
    });
  });

  group('downloads (ADR-0010)', () {
    late HttpServer server;
    late Directory cache;
    late List<HttpRequest> requests;
    late Map<String, List<int>> files;
    // Holds a response open after its first chunk, for the cancel test.
    Completer<void>? hold;
    final downloader = DictionaryDownloader(allowHttp: true);

    setUp(() async {
      cache = Directory.systemTemp.createTempSync('doxa-download-');
      requests = [];
      files = {};
      hold = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request);
        final path = request.uri.path;
        if (path == '/moved.zip') {
          await request.response.redirect(Uri.parse('/pack.zip'));
          return;
        }
        final body = files[path];
        if (body == null) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.contentLength = body.length;
        if (hold case final hold?) {
          // Past the server's output buffer, so the first part is sent.
          request.response.add(body.sublist(0, 65536));
          await request.response.flush();
          await hold.future;
          request.response.add(body.sublist(65536));
        } else {
          request.response.add(body);
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      hold?.complete();
      await server.close(force: true);
      cache.deleteSync(recursive: true);
    });

    Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    List<String> leftovers() =>
        cache.listSync().map((e) => e.uri.pathSegments.last).toList();

    test('fetches the catalogue with a plain request', () async {
      final pack = List<int>.generate(100, (i) => i);
      files['/v1/dictionaries.json'] = utf8.encode(
        jsonEncode({
          'format': 1,
          'packs': [packJson('pt', pack)],
        }),
      );
      final packs = await downloader.fetchCatalog(at('/v1/dictionaries.json'));
      expect(packs.single.url, at('/v1/pack.zip'));

      // NFR-SEC-001: no identifiers, cookies or query parameters.
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.uri.query, isEmpty);
      expect(request.cookies, isEmpty);
      expect(
        request.headers.value(HttpHeaders.userAgentHeader),
        DictionaryDownloader.userAgent,
      );
    });

    test('downloads a good pack, following a redirect', () async {
      final bytes = List<int>.generate(300000, (i) => i % 251);
      files['/pack.zip'] = bytes;
      final pack = parseCatalog(
        jsonEncode({
          'format': 1,
          'packs': [packJson('pt', bytes, url: 'moved.zip')],
        }),
        at('/dictionaries.json'),
        allowHttp: true,
      ).single;
      final progress = <int>[];
      final file = await downloader.download(
        pack,
        cache,
        onProgress: progress.add,
      );
      expect(file.readAsBytesSync(), bytes);
      expect(progress.last, bytes.length);
      expect(progress, orderedEquals([...progress]..sort()));
    });

    test('a pack whose hash does not match leaves nothing behind', () async {
      final bytes = List<int>.filled(1000, 7);
      files['/pack.zip'] = bytes;
      final wrong = sha256.convert([1]).toString();
      final pack = parseCatalog(
        jsonEncode({
          'format': 1,
          'packs': [packJson('pt', bytes, sha: wrong)],
        }),
        at('/dictionaries.json'),
        allowHttp: true,
      ).single;
      await expectLater(
        downloader.download(pack, cache),
        throwsA(_error(DownloadError.corrupt)),
      );
      expect(leftovers(), isEmpty);
    });

    test('cancelling stops the download and leaves nothing behind', () async {
      final bytes = List<int>.filled(200000, 3);
      files['/pack.zip'] = bytes;
      hold = Completer<void>();
      final pack = parseCatalog(
        jsonEncode({
          'format': 1,
          'packs': [packJson('pt', bytes)],
        }),
        at('/dictionaries.json'),
        allowHttp: true,
      ).single;
      final cancel = DownloadCancel();
      final download = downloader.download(
        pack,
        cache,
        cancel: cancel,
        onProgress: (_) => cancel.cancel(),
      );
      await expectLater(download, throwsA(_error(DownloadError.cancelled)));
      expect(leftovers(), isEmpty);
    });

    test('a server error or no server is reported, not thrown raw', () async {
      await expectLater(
        downloader.fetchCatalog(at('/missing.json')),
        throwsA(_error(DownloadError.failed)),
      );
      final port = server.port;
      await server.close(force: true);
      await expectLater(
        downloader.fetchCatalog(
          Uri.parse('http://127.0.0.1:$port/dictionaries.json'),
        ),
        throwsA(_error(DownloadError.offline)),
      );
      // Rebind so tearDown can close a server.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    test('cleans up downloads a dead process left behind', () async {
      File('${cache.path}/doxa-dictionary-download-1.zip')
          .writeAsBytesSync([1]);
      File('${cache.path}/other.txt').writeAsBytesSync([1]);
      await DictionaryDownloader.cleanUp(cache);
      expect(leftovers(), ['other.txt']);
    });
  });
}

Matcher _error(DownloadError error) =>
    isA<DownloadException>().having((e) => e.error, 'error', error);
