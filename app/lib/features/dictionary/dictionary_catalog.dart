// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../src/app_version.dart';

/// The catalogue of the dictionary packs Doxa builds, published with the
/// release that matches the app (ADR-0010). Only this address is fixed in
/// the app; each pack's address and hash come from the catalogue.
final Uri catalogUri = Uri.https(
  'github.com',
  '/Frerol/doxa-pdf/releases/download/v${appVersion.split('+').first}/dictionaries.json',
);

/// The catalogue format this app reads.
const catalogFormat = 1;

/// The largest catalogue the app reads, so a broken server cannot exhaust
/// memory. A real one is a few KB.
const maxCatalogBytes = 1024 * 1024;

/// One dictionary pack in the catalogue (ADR-0010).
final class CatalogPack {
  const CatalogPack({
    required this.id,
    required this.name,
    required this.language,
    required this.bookName,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
    required this.unpackedBytes,
    required this.ifoSha256,
    required this.source,
    required this.licence,
    this.description = '',
  });

  /// A stable name, for example `doxa-pt`.
  final String id;

  /// The name shown in the list, for example "Português".
  final String name;

  /// The BCP 47 code of the headwords' language, for example `pt`.
  final String language;

  /// The `.ifo` bookname, which tells an installed pack apart.
  final String bookName;

  /// The `.zip` to download.
  final Uri url;

  /// The `.zip`'s SHA-256, lowercase hex.
  final String sha256;
  final int sizeBytes;

  /// Bytes on disk once extracted, for the free-space check.
  final int unpackedBytes;

  /// The SHA-256 of the pack's `.ifo`, which changes with each build: an
  /// installed pack with another one has a newer build in the catalogue.
  final String ifoSha256;
  final String source;
  final String licence;
  final String description;
}

class CatalogFormatException implements Exception {
  const CatalogFormatException(this.message);

  final String message;

  @override
  String toString() => 'CatalogFormatException: $message';
}

/// Reads a catalogue fetched from [base]. Relative pack addresses resolve
/// against [base]. A pack with a missing or wrong field, or one whose
/// address is not HTTPS (unless [allowHttp], for tests), is left out, so
/// that a newer catalogue still lists what this app understands.
List<CatalogPack> parseCatalog(
  String text,
  Uri base, {
  bool allowHttp = false,
}) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (error) {
    throw CatalogFormatException(error.message);
  }
  if (json is! Map<String, Object?> || json['format'] != catalogFormat) {
    throw const CatalogFormatException('Unknown catalogue format');
  }
  final packs = json['packs'];
  if (packs is! List<Object?>) {
    throw const CatalogFormatException('No pack list');
  }
  final ids = <String>{};
  return [
    for (final item in packs)
      if (_pack(item, base, allowHttp) case final pack?)
        if (ids.add(pack.id)) pack,
  ];
}

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

CatalogPack? _pack(Object? item, Uri base, bool allowHttp) {
  if (item is! Map<String, Object?>) return null;
  String? text(String key) => switch (item[key]) {
    final String value when value.trim().isNotEmpty => value.trim(),
    _ => null,
  };
  int? count(String key) => switch (item[key]) {
    final int value when value > 0 => value,
    _ => null,
  };
  // Only definition packs belong here; translation packs go to the
  // separate Translate action (#100).
  if ((text('kind') ?? 'definitions') != 'definitions') return null;
  final address = text('url');
  final Uri url;
  try {
    if (address == null) return null;
    url = base.resolve(address);
  } on FormatException {
    return null;
  }
  if (url.scheme != 'https' && !(allowHttp && url.scheme == 'http')) {
    return null;
  }
  final sha = text('sha256')?.toLowerCase();
  final ifoSha = text('ifoSha256')?.toLowerCase();
  if (sha == null || !_hex64.hasMatch(sha)) return null;
  if (ifoSha == null || !_hex64.hasMatch(ifoSha)) return null;
  final id = text('id');
  final name = text('name');
  final language = text('language');
  final bookName = text('bookName');
  final size = count('size');
  final unpacked = count('unpackedSize');
  if (id == null ||
      name == null ||
      language == null ||
      bookName == null ||
      size == null ||
      unpacked == null) {
    return null;
  }
  return CatalogPack(
    id: id,
    name: name,
    language: language,
    bookName: bookName,
    url: url,
    sha256: sha,
    sizeBytes: size,
    unpackedBytes: unpacked,
    ifoSha256: ifoSha,
    source: text('source') ?? '',
    licence: text('licence') ?? '',
    description: text('description') ?? '',
  );
}

/// Why a catalogue fetch or a pack download failed.
enum DownloadError {
  /// No network, or the server could not be reached.
  offline,

  /// The server answered with an error, or the catalogue is unreadable.
  failed,

  /// The downloaded file is not the one the catalogue lists.
  corrupt,

  /// The user cancelled the download.
  cancelled,
}

class DownloadException implements Exception {
  const DownloadException(this.error);

  final DownloadError error;

  @override
  String toString() => 'DownloadException(${error.name})';
}

/// Cancels a running [DictionaryDownloader.download].
final class DownloadCancel {
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// The name prefix of downloads in the cache, so that one left behind by a
/// process that died can be cleaned up.
const _partPrefix = 'doxa-dictionary-download-';

/// Fetches the catalogue and downloads packs over plain HTTPS `GET`s with a
/// generic user agent and no cookies, identifiers or query parameters
/// (ADR-0010). Nothing is fetched unless the user opens the list or taps a
/// pack.
class DictionaryDownloader {
  DictionaryDownloader({HttpClient Function()? client, this.allowHttp = false})
    : _client = client ?? HttpClient.new;

  final HttpClient Function() _client;

  /// Accepts `http` pack addresses, for tests against a local server.
  final bool allowHttp;

  /// The user agent of every request: the app's name, nothing else.
  static const userAgent = 'DoxaPDF';

  HttpClient _newClient() => _client()
    ..userAgent = userAgent
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 5);

  /// The packs listed at [uri].
  Future<List<CatalogPack>> fetchCatalog(Uri uri) async {
    final client = _newClient();
    try {
      final response = await _get(client, uri);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_stallTimeout)) {
        bytes.add(chunk);
        if (bytes.length > maxCatalogBytes) {
          throw const DownloadException(DownloadError.failed);
        }
      }
      return parseCatalog(
        utf8.decode(bytes.takeBytes()),
        uri,
        allowHttp: allowHttp,
      );
    } on DownloadException {
      rethrow;
    } on CatalogFormatException {
      throw const DownloadException(DownloadError.failed);
    } on FormatException {
      throw const DownloadException(DownloadError.failed);
    } on Object catch (error) {
      throw DownloadException(_networkError(error));
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads [pack] into [directory] and returns the file once its
  /// SHA-256 matches the catalogue. [onProgress] gets the bytes received
  /// so far. On failure or [cancel], nothing is left behind.
  Future<File> download(
    CatalogPack pack,
    Directory directory, {
    void Function(int received)? onProgress,
    DownloadCancel? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      throw const DownloadException(DownloadError.cancelled);
    }
    final file = File(
      '${directory.path}/$_partPrefix${DateTime.now().microsecondsSinceEpoch}.zip',
    );
    final client = _newClient();
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    IOSink? sink;
    StreamSubscription<List<int>>? subscription;
    try {
      final response = await _cancellable(_get(client, pack.url), cancel);
      final declared = response.contentLength;
      if (declared >= 0 && declared != pack.sizeBytes) {
        throw const DownloadException(DownloadError.corrupt);
      }
      await directory.create(recursive: true);
      final out = sink = file.openWrite();
      var received = 0;
      final done = Completer<void>();
      subscription = response
          .timeout(_stallTimeout)
          .listen(
            (chunk) {
              received += chunk.length;
              if (received > pack.sizeBytes) {
                if (!done.isCompleted) {
                  done.completeError(
                    const DownloadException(DownloadError.corrupt),
                  );
                }
                return;
              }
              hash.add(chunk);
              out.add(chunk);
              onProgress?.call(received);
            },
            onError: (Object error) {
              if (!done.isCompleted) done.completeError(error);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
      await _cancellable(done.future, cancel);
      await out.flush();
      await out.close();
      sink = null;
      hash.close();
      if (received != pack.sizeBytes || digest.value != pack.sha256) {
        throw const DownloadException(DownloadError.corrupt);
      }
      return file;
    } on Object catch (error) {
      await subscription?.cancel();
      client.close(force: true);
      try {
        await sink?.close();
      } on Object {
        // The file is deleted below.
      }
      if (await file.exists()) await file.delete();
      if (error is DownloadException) rethrow;
      throw DownloadException(_networkError(error));
    } finally {
      client.close(force: true);
    }
  }

  /// Deletes downloads that a process which died left in [directory].
  static Future<void> cleanUp(Directory directory) async {
    if (!await directory.exists()) return;
    await for (final entry in directory.list(followLinks: false)) {
      final name = entry.uri.pathSegments.last;
      if (entry is File && name.startsWith(_partPrefix)) {
        try {
          await entry.delete();
        } on FileSystemException {
          // Another start will try again.
        }
      }
    }
  }

  static const _stallTimeout = Duration(seconds: 30);

  Future<HttpClientResponse> _get(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.followRedirects = true;
    request.maxRedirects = 5;
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      unawaited(response.drain<void>().catchError((_) {}));
      throw const DownloadException(DownloadError.failed);
    }
    return response;
  }

  static Future<T> _cancellable<T>(Future<T> future, DownloadCancel? cancel) {
    if (cancel == null) return future;
    return Future.any([
      future,
      cancel._cancelled.future.then<T>(
        (_) => throw const DownloadException(DownloadError.cancelled),
      ),
    ]);
  }

  static DownloadError _networkError(Object error) => switch (error) {
    SocketException() || TimeoutException() => DownloadError.offline,
    _ => DownloadError.failed,
  };
}

/// The SHA-256 of a file, lowercase hex; for the installed `.ifo` files.
Future<String> fileSha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

final class _DigestSink implements Sink<Digest> {
  String? value;

  @override
  void add(Digest data) => value = data.toString();

  @override
  void close() {}
}
