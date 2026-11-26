// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math';

import 'dictionary_data.dart';
import 'dictionary_field.dart';
import 'dictionary_format_exception.dart';
import 'lookup_normalization.dart';
import 'stardict_index.dart';
import 'stardict_info.dart';

/// A matching headword with its zero-based .idx ordinal and unsanitized fields.
typedef DictionaryEntry = ({
  String headword,
  int ordinal,
  List<DictionaryField> fields,
});

/// Discovery results, with each list ordered by .ifo path.
typedef DictionaryDiscovery = ({
  List<({File ifo, StarDictInfo info})> valid,
  List<({File ifo, DictionaryFormatException error})> invalid,
});

/// The unique nearest of the supplied suggestions by Levenshtein distance.
/// The query is trimmed, and both sides use the same case and diacritic
/// folding as [Dictionary.suggest]. Repeated headwords count only once.
String? closestSuggestion(String query, Iterable<String> suggestions) {
  final key = foldDiacritics(trimLookupQuery(query)).runes.toList();
  String? closest;
  int? bestDistance;
  for (final word in suggestions.toSet()) {
    final distance = _editDistance(key, foldDiacritics(word).runes);
    if (bestDistance == null || distance < bestDistance) {
      bestDistance = distance;
      closest = word;
    } else if (distance == bestDistance) {
      closest = null;
    }
  }
  return closest;
}

int _editDistance(List<int> key, Iterable<int> word) {
  final row = List.generate(key.length + 1, (i) => i);
  for (final rune in word) {
    var diagonal = row[0]++;
    for (var i = 1; i < row.length; i++) {
      final above = row[i];
      row[i] = min(
        diagonal + (rune == key[i - 1] ? 0 : 1),
        1 + min(above, row[i - 1]),
      );
      diagonal = above;
    }
  }
  return row.last;
}

/// A synchronous StarDict reader. Open, use and close it in the same isolate.
final class Dictionary {
  Dictionary._(this.info, this._index, this._synonyms, this._data);

  final StarDictInfo info;
  final StarDictIndex _index;
  final StarDictSynonyms? _synonyms;
  final DictionaryData _data;
  late final _caseIndex = _buildNormalizedIndex((word) => word.toLowerCase());
  late final _diacriticIndex = _buildNormalizedIndex(foldDiacritics);
  // Folded once, on the first suggestion, so later calls only compare.
  late final List<List<int>> _foldedHeadwords = [
    for (var i = 0; i < _index.length; i++)
      foldDiacritics(_index[i].headword).runes.toList(growable: false),
  ];

  /// Opens an .ifo set and validates its indexes and definition ranges.
  /// Definition payloads are decoded on demand. The caller owns [close].
  static Dictionary open(File ifo) {
    if (!ifo.path.endsWith('.ifo')) {
      throw const DictionaryFormatException('Expected an .ifo file');
    }
    final base = ifo.path.substring(0, ifo.path.length - '.ifo'.length);
    try {
      final info = StarDictInfo.parse(ifo.readAsBytesSync());
      final sequence = info.sameTypeSequence;
      if (sequence != null && !RegExp(r'^[A-Za-z]+$').hasMatch(sequence)) {
        throw const DictionaryFormatException('Invalid sametypesequence');
      }
      final idx = File('$base.idx');
      final gzip = !_present(idx);
      final index = StarDictIndex.parse(
        (gzip ? File('$base.idx.gz') : idx).readAsBytesSync(),
        info,
        gzip: gzip,
      );
      final syn = File('$base.syn');
      final synDz = File('$base.syn.dz');
      final StarDictSynonyms? synonyms;
      if (_present(syn)) {
        synonyms = StarDictSynonyms.parse(syn.readAsBytesSync(), info);
      } else if (_present(synDz)) {
        synonyms = StarDictSynonyms.parse(
          synDz.readAsBytesSync(),
          info,
          gzip: true,
        );
      } else {
        if ((info.synWordCount ?? 0) > 0) {
          throw const DictionaryFormatException('Missing declared .syn file');
        }
        synonyms = null;
      }
      final plain = File('$base.dict');
      final data = _present(plain)
          ? DictionaryData.openPlain(plain)
          : DictionaryData.openDictzip(File('$base.dict.dz'));
      try {
        for (var ordinal = 0; ordinal < index.length; ordinal++) {
          final (:offset, :size, headword: _) = index[ordinal];
          if (offset > data.length || size > data.length - offset) {
            throw DictionaryFormatException(
              'Definition range outside dictionary data at ordinal $ordinal',
            );
          }
        }
        return Dictionary._(info, index, synonyms, data);
      } on Object {
        data.close();
        rethrow;
      }
    } on FileSystemException catch (error) {
      throw DictionaryFormatException(
        'Cannot read StarDict file: ${error.path} (${error.message})',
      );
    }
  }

  static bool _present(File file) =>
      FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.notFound;

  /// Validates .ifo sets recursively without following symbolic links.
  /// Valid results contain metadata and paths, with no open data handles.
  static DictionaryDiscovery findAll(Directory dir) {
    final files =
        dir
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.ifo'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final valid = <({File ifo, StarDictInfo info})>[];
    final invalid = <({File ifo, DictionaryFormatException error})>[];
    for (final ifo in files) {
      try {
        final dictionary = open(ifo);
        final info = dictionary.info;
        dictionary.close();
        valid.add((ifo: ifo, info: info));
      } on DictionaryFormatException catch (error) {
        invalid.add((ifo: ifo, error: error));
      }
    }
    return (
      valid: List.unmodifiable(valid),
      invalid: List.unmodifiable(invalid),
    );
  }

  /// Returns matches from the first successful lookup level in .idx order.
  List<DictionaryEntry> lookup(String query) {
    final word = trimLookupQuery(query);
    if (word.isEmpty) return [];
    final exact = {..._index.lookup(word), ...?_synonyms?.lookup(word)};
    final ordinals = exact.isNotEmpty
        ? exact
        : _caseIndex[word.toLowerCase()] ??
              _diacriticIndex[foldDiacritics(word)] ??
              const <int>{};
    return [
      for (final ordinal in ordinals.toList()..sort()) _readEntry(ordinal),
    ];
  }

  DictionaryEntry _readEntry(int ordinal) {
    final (:headword, :offset, :size) = _index[ordinal];
    try {
      return (
        headword: headword,
        ordinal: ordinal,
        fields: DictionaryField.parse(
          _data.read(offset, size),
          sameTypeSequence: info.sameTypeSequence,
        ),
      );
    } on FileSystemException catch (error) {
      throw DictionaryFormatException(
        'Cannot read definition: ${error.message}',
      );
    }
  }

  Map<String, Set<int>> _buildNormalizedIndex(String Function(String) fold) {
    final result = <String, Set<int>>{};
    for (var i = 0; i < _index.length; i++) {
      (result[fold(_index[i].headword)] ??= {}).add(i);
    }
    final synonyms = _synonyms;
    if (synonyms != null) {
      for (var i = 0; i < synonyms.length; i++) {
        (result[fold(synonyms.aliasAt(i))] ??= {}).add(synonyms.ordinalAt(i));
      }
    }
    return result;
  }

  /// Returns distinct headwords tied for the longest nonempty shared
  /// case- and diacritic-folded prefix, in .idx order.
  List<String> suggest(String query, {int limit = 10}) {
    final key = foldDiacritics(trimLookupQuery(query)).runes.toList();
    if (limit <= 0 || key.isEmpty) return [];
    final matches = <String>{};
    var longest = 0;
    for (var i = 0; i < _index.length; i++) {
      final word = _index[i].headword;
      var shared = 0;
      for (final rune in _foldedHeadwords[i]) {
        if (shared == key.length || rune != key[shared]) break;
        shared++;
      }
      if (shared == 0 || shared < longest) continue;
      if (shared > longest) {
        matches.clear();
        longest = shared;
      }
      if (matches.length < limit) matches.add(word);
    }
    return matches.toList();
  }

  /// Releases the underlying definition file.
  void close() => _data.close();
}
