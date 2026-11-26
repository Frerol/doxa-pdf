// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:test/test.dart';

const _root = 'test/fixtures/lookup';
final _formatError = throwsA(isA<DictionaryFormatException>());

Dictionary _open(String path) {
  final dictionary = Dictionary.open(File('$_root/$path.ifo'));
  addTearDown(dictionary.close);
  return dictionary;
}

Iterable<String> _words(List<DictionaryEntry> entries) =>
    entries.map((entry) => entry.headword);

void main() {
  test('FR-TEXT-010 ranks distinct suggestions on folded, trimmed forms', () {
    expect(
      closestSuggestion(' “INTANGÍVEIS!” ', ['intangível', 'intangivelmente']),
      'intangível',
    );
    expect(closestSuggestion('cas', ['cat', 'car', 'cat']), isNull);
    expect(closestSuggestion(' “cás!” ', ['cas', 'cás']), isNull);
    expect(closestSuggestion('cats', ['cat', 'cat']), 'cat');
  });

  group('StarDict sets (FR-TEXT-009)', () {
    test('prefers .idx and .dict when both companions are present', () {
      final dictionary = _open('study');
      final entry = dictionary.lookup('acao').single;
      expect(entry.fields.single.type, 'm');
      expect(entry.fields.single.text, 'Sample for acao');
    });

    test('opens .idx.gz and .dict.dz with no .syn', () {
      final dictionary = _open('nested/accented');
      final entry = dictionary.lookup('ação').single;
      expect(entry.fields.single.text, 'Sample for ação');
    });

    test('findAll walks nested directories and reports invalid sets', () {
      final result = Dictionary.findAll(Directory(_root));
      expect(result.valid.map((set) => set.info.bookName), [
        'accented',
        'study',
      ]);
      expect(result.invalid.single.ifo.path, endsWith('/nested/invalid.ifo'));
      expect(result.invalid.single.error.message, contains('UTF-8'));
    });
  });

  group('lookup (FR-TEXT-010)', () {
    test('merges exact hits and aliases by ordinal before folding', () {
      final dictionary = _open('study');
      final entries = dictionary.lookup('Alvo');
      expect(_words(entries), ['Alvo', 'Alvo', 'arco', 'zebra']);
      final ordinals = entries.map((entry) => entry.ordinal).toList();
      expect(ordinals, ordinals.toSet().toList()..sort());
    });

    test(
      'folds Unicode case after an exact lookup and stops before accents',
      () {
        final dictionary = _open('study');
        expect(_words(dictionary.lookup('ALVO')), ['ALVO', 'zebra']);
        expect(_words(dictionary.lookup('alvo')), [
          'ALVO',
          'Alvo',
          'Alvo',
          'arco',
          'zebra',
        ]);
        expect(_words(dictionary.lookup('ÉCOLE')), ['co-op', 'école']);
      },
    );

    test('merges direct hits and aliases at the diacritic-folded level', () {
      final dictionary = _open('study');
      expect(_words(dictionary.lookup('âlvo')), [
        'act',
        'ALVO',
        'Alvo',
        'Alvo',
        'arco',
        'zebra',
        'Álvo',
      ]);
      expect(_words(dictionary.lookup('zaba')), ['Žaba']);
    });

    test('matches composed and decomposed accents in both directions', () {
      final plain = _open('study');
      const decomposed = 'ac\u0327a\u0303o';
      for (final query in ['ação', decomposed]) {
        expect(_words(plain.lookup(query)), ['acao']);
      }
      final accented = _open('nested/accented');
      expect(_words(accented.lookup('acao')), [decomposed, 'ação']);
    });

    test(
      'trims whitespace and punctuation while preserving internal marks',
      () {
        final dictionary = _open('study');
        expect(_words(dictionary.lookup(' \t« ( co-op ) »\n')), ['co-op']);
        expect(dictionary.lookup(' « ! » '), isEmpty);
        expect(dictionary.lookup('missing'), isEmpty);
      },
    );
  });

  group('suggestions (FR-TEXT-010)', () {
    test(
      'ranks longest normalized prefix and limits results in .idx order',
      () {
        final dictionary = _open('study');
        expect(dictionary.suggest(' « ÁCZZ » '), ['acao', 'acorn', 'act']);
        expect(dictionary.suggest(' « ÁCZZ » ', limit: 2), ['acao', 'acorn']);
        expect(dictionary.suggest('álvzz'), ['ALVO', 'Alvo', 'Álvo']);
        expect(dictionary.suggest('acorzz', limit: 1), ['acorn']);
        expect(dictionary.suggest('ac', limit: 0), isEmpty);
        expect(dictionary.suggest('?'), isEmpty);
        expect(dictionary.suggest('qq'), isEmpty);
      },
    );
  });

  group('malformed sets', () {
    late Directory scratch;
    late File ifo;

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('doxa-lookup-');
      for (final extension in [
        'ifo',
        'idx',
        'dict',
        'syn',
        'idx.gz',
        'dict.dz',
      ]) {
        File('$_root/study.$extension')
            .copySync('${scratch.path}/study.$extension');
      }
      ifo = File('${scratch.path}/study.ifo');
    });
    tearDown(() => scratch.deleteSync(recursive: true));

    File companion(String extension) =>
        File('${scratch.path}/study.$extension');

    test('rejects a wrong .idx size and truncated definition ranges', () {
      final idx = companion('idx');
      final bytes = idx.readAsBytesSync();
      idx.writeAsBytesSync(bytes.sublist(1));
      expect(() => Dictionary.open(ifo), _formatError);
      idx.writeAsBytesSync(bytes);
      companion('dict').writeAsBytesSync([]);
      expect(() => Dictionary.open(ifo), _formatError);
    });

    test('rejects missing declared synonyms and missing data', () {
      final syn = companion('syn')..deleteSync();
      expect(() => Dictionary.open(ifo), _formatError);
      File('$_root/study.syn').copySync(syn.path);
      companion('dict').deleteSync();
      companion('dict.dz').deleteSync();
      expect(() => Dictionary.open(ifo), _formatError);
    });

    test('reads a gzip-compressed .syn.dz in place of .syn', () {
      final syn = companion('syn');
      final aliases = Dictionary.open(ifo);
      final expected = _words(aliases.lookup('Alvo')).toList();
      aliases.close();
      companion('syn.dz').writeAsBytesSync(gzip.encode(syn.readAsBytesSync()));
      syn.deleteSync();
      final dictionary = Dictionary.open(ifo);
      addTearDown(dictionary.close);
      expect(_words(dictionary.lookup('Alvo')), expected);
    });

    test('rejects a damaged .syn.dz', () {
      final syn = companion('syn');
      final packed = gzip.encode(syn.readAsBytesSync());
      syn.deleteSync();
      companion('syn.dz')
          .writeAsBytesSync(packed.sublist(0, packed.length - 6));
      expect(() => Dictionary.open(ifo), _formatError);
    });

    test('reports bad UTF-8 when its definition is read', () {
      final dict = companion('dict');
      final bytes = dict.readAsBytesSync()..[0] = 0xff;
      dict.writeAsBytesSync(bytes);
      final dictionary = Dictionary.open(ifo);
      addTearDown(dictionary.close);
      expect(_words(dictionary.lookup('act')), ['act']);
      expect(() => dictionary.lookup('acao'), _formatError);
    });
  });
}
