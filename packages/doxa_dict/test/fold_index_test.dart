// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:test/test.dart';

void main() {
  group('FR-TEXT-010 folded sidecar', () {
    late Directory scratch;
    late File ifo;
    late File fold;

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('doxa-fold-');
      ifo = File('${scratch.path}/sample.ifo');
      fold = File('${scratch.path}/sample.fold');
    });
    tearDown(() => scratch.deleteSync(recursive: true));

    Dictionary open() {
      final dictionary = Dictionary.open(ifo, scanWithoutFoldIndex: false);
      addTearDown(dictionary.close);
      return dictionary;
    }

    test(
      'matches the streaming reader on existing plain and gzip fixtures',
      () {
        for (final (name, extensions) in [
          ('study', ['ifo', 'idx', 'syn', 'dict']),
          ('nested/accented', ['ifo', 'idx.gz', 'dict.dz']),
        ]) {
          for (final extension in extensions) {
            File('test/fixtures/lookup/$name.$extension')
                .copySync('${scratch.path}/sample.$extension');
          }
          if (name != 'study') {
            File('${scratch.path}/sample.idx').deleteSync();
            File('${scratch.path}/sample.syn').deleteSync();
            File('${scratch.path}/sample.dict').deleteSync();
          }
          if (fold.existsSync()) fold.deleteSync();
          final scan = Dictionary.open(ifo);
          addTearDown(scan.close);
          Dictionary.buildFoldIndex(ifo.path);
          final indexed = open();
          expect(indexed.hasFoldIndex, isTrue);
          for (final query in [
            'ALVO',
            'alvo',
            'âlvo',
            'ÉCOLE',
            'zaba',
            'ação',
            'ac\u0327a\u0303o',
            'acao',
            ' « ÁCZZ » ',
            'álvzz',
            'acorzz',
            'ac',
            '?',
            'qq',
          ]) {
            expect(
              indexed.lookup(query).map((e) => e.ordinal),
              scan.lookup(query).map((e) => e.ordinal),
              reason: query,
            );
            for (final limit in [0, 1, 2, 10]) {
              expect(
                indexed.suggest(query, limit: limit),
                scan.suggest(query, limit: limit),
                reason: query,
              );
            }
          }
        }
      },
    );

    test('keeps exact lookup usable and attaches a completed build', () {
      _writeSet(ifo, ['Alvo']);
      final dictionary = open();
      expect(dictionary.hasFoldIndex, isFalse);
      expect(dictionary.lookup('Alvo').single.ordinal, 0);
      expect(dictionary.lookup('alvo'), isEmpty);
      expect(dictionary.suggest('alv'), isEmpty);
      Dictionary.buildFoldIndex(ifo.path);
      dictionary.refreshFoldIndex();
      expect(dictionary.hasFoldIndex, isTrue);
      expect(dictionary.lookup('alvo').single.headword, 'Alvo');
    });

    test('rebuilds after same-size idx and compressed syn edits', () {
      _writeSet(ifo, ['Alvo'], alias: 'First', gzip: true);
      final idx = File('${scratch.path}/sample.idx.gz');
      final syn = File('${scratch.path}/sample.syn.dz');
      final originalStamp = DateTime.utc(2020);
      final editedStamp = DateTime.utc(2021);
      idx.setLastModifiedSync(originalStamp);
      syn.setLastModifiedSync(originalStamp);
      final idxSize = idx.lengthSync();
      final synSize = syn.lengthSync();

      Dictionary.buildFoldIndex(ifo.path);
      expect(open().lookup('first').single.headword, 'Alvo');
      _writeSet(ifo, ['Alva'], alias: 'First', gzip: true);
      idx.setLastModifiedSync(editedStamp);
      syn.setLastModifiedSync(originalStamp);
      expect(idx.lengthSync(), idxSize);
      expect(open().hasFoldIndex, isFalse);
      Dictionary.buildFoldIndex(ifo.path);
      expect(open().lookup('alva').single.headword, 'Alva');

      _writeSet(ifo, ['Alva'], alias: 'Other', gzip: true);
      idx.setLastModifiedSync(editedStamp);
      syn.setLastModifiedSync(editedStamp);
      expect(syn.lengthSync(), synSize);
      expect(open().hasFoldIndex, isFalse);
      Dictionary.buildFoldIndex(ifo.path);
      final rebuilt = open();
      expect(rebuilt.lookup('first'), isEmpty);
      expect(rebuilt.lookup('other').single.headword, 'Alva');
    });

    test(
      'discards a truncated header and a corrupt row, then builds again',
      () {
        _writeSet(ifo, ['Alvo']);
        Dictionary.buildFoldIndex(ifo.path);
        fold.writeAsBytesSync([1, 2, 3]);
        expect(open().hasFoldIndex, isFalse);
        Dictionary.buildFoldIndex(ifo.path);
        final bytes = fold.readAsBytesSync();
        // The first case row follows the version-1 header.
        bytes[88] ^= 1;
        fold.writeAsBytesSync(bytes);
        final damaged = open();
        expect(damaged.lookup('Alvo').single.headword, 'Alvo');
        expect(damaged.lookup('alvo'), isEmpty);
        expect(damaged.hasFoldIndex, isFalse);
        Dictionary.buildFoldIndex(ifo.path);
        damaged.refreshFoldIndex();
        expect(damaged.lookup('alvo').single.headword, 'Alvo');
      },
    );

    test(
      'counts complete Unicode code points and ignores aliases in suggestions',
      () {
        _writeSet(ifo, [
          'Αθήνα',
          'ação😀',
          'ac\u0327a\u0303o😀',
          'a😁z',
          '😀a',
        ], alias: 'a😀extra');
        Dictionary.buildFoldIndex(ifo.path);
        final dictionary = open();
        expect(dictionary.lookup('ΑΘΉΝΑ').single.headword, 'Αθήνα');
        expect(dictionary.lookup('ACAO😀').map((e) => e.headword), [
          'ac\u0327a\u0303o😀',
          'ação😀',
        ]);
        expect(dictionary.lookup('A😀EXTRA'), hasLength(1));
        expect(dictionary.suggest('a😀extra'), [
          'ac\u0327a\u0303o😀',
          'ação😀',
          'a😁z',
        ]);
        expect(dictionary.suggest('😁x'), isEmpty);
        expect(dictionary.suggest('😀z'), ['😀a']);
      },
    );

    test('handles a StarDict record crossing the builder read boundary', () {
      final word = 'a' * (65536 - 2);
      _writeSet(ifo, [word, 'Zulu']);
      Dictionary.buildFoldIndex(ifo.path);
      expect(open().lookup('ZULU').single.headword, 'Zulu');
    });
  });
}

// Generated StarDict sets with synthetic headwords and one shared definition.
void _writeSet(
  File ifo,
  List<String> words, {
  String? alias,
  bool gzip = false,
}) {
  words.sort((a, b) {
    List<int> key(String word) => utf8.encode(
      word.replaceAllMapped(RegExp('[A-Z]'), (m) => m[0]!.toLowerCase()),
    );
    final left = key(a);
    final right = key(b);
    for (var i = 0; i < left.length && i < right.length; i++) {
      if (left[i] != right[i]) return left[i] - right[i];
    }
    return left.length - right.length;
  });
  final base = ifo.path.substring(0, ifo.path.length - 4);
  final index = BytesBuilder();
  for (final word in words) {
    index
      ..add(utf8.encode(word))
      ..addByte(0)
      ..add((ByteData(8)..setUint32(4, 1)).buffer.asUint8List());
  }
  final bytes = index.takeBytes();
  File('$base.idx${gzip ? '.gz' : ''}')
      .writeAsBytesSync(gzip ? GZipCodec().encode(bytes) : bytes);
  File('$base.dict').writeAsStringSync('x');
  if (alias != null) {
    final syn = [...utf8.encode(alias), 0, 0, 0, 0, 0];
    File('$base.syn${gzip ? '.dz' : ''}')
        .writeAsBytesSync(gzip ? GZipCodec().encode(syn) : syn);
  }
  ifo.writeAsStringSync(
    "StarDict's dict ifo file\nversion=3.0.0\nbookname=Fold fixture\n"
    'wordcount=${words.length}\nidxfilesize=${bytes.length}\nsametypesequence=m\n'
    '${alias == null ? '' : 'synwordcount=1\n'}',
  );
}
