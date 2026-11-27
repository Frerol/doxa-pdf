// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'dictionary_data.dart';
import 'dictionary_field.dart';
import 'dictionary_format_exception.dart';
import 'fold_index.dart';
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
  Dictionary._(this._source, this._data, this._scanWithoutFoldIndex);

  final _IndexSource _source;
  final DictionaryData _data;
  final bool _scanWithoutFoldIndex;
  FoldIndex? _fold;

  StarDictInfo get info => _source.info;
  StarDictIndex get _index => _source.index;
  StarDictSynonyms? get _synonyms => _source.synonyms;

  /// Builds Doxa's sidecar atomically. Call in a short-lived isolate.
  /// A valid existing sidecar can be reused by opening it with [open].
  static void buildFoldIndex(String ifoPath) {
    final base = _IndexSource.baseOf(File(ifoPath));
    final info = StarDictInfo.parse(File(ifoPath).readAsBytesSync());
    final (idx, idxStamp) = _IndexSource.select('$base.idx', '.gz');
    final (syn, synStamp) = _IndexSource.select('$base.syn', '.dz');
    _IndexSource.checkSources(info, idx, syn);
    final words = info.wordCount;
    final aliases = info.synWordCount ?? 0;
    final idxLimit = idxStamp.kind == 2
        ? StarDictIndex.maxGzipIndexSize
        : idxStamp.size;
    final synLimit = synStamp.kind == 2
        ? StarDictIndex.maxGzipIndexSize
        : synStamp.size;
    if (info.idxFileSize > idxLimit ||
        words > info.idxFileSize ~/ (info.idxOffsetBits ~/ 8 + 5) ||
        aliases > synLimit ~/ 5) {
      throw const DictionaryFormatException('Invalid index size or count');
    }

    writeFoldIndex(
      File('$base.fold'),
      idxStamp,
      synStamp,
      words,
      words + aliases,
      (visit) {
        visitStarDictWords(
          idx!,
          info,
          synonyms: false,
          gzip: idxStamp.kind == 2,
          visit: visit,
        );
        if (syn != null) {
          visitStarDictWords(
            syn,
            info,
            synonyms: true,
            gzip: synStamp.kind == 2,
            visit: visit,
          );
        }
      },
      foldDiacritics,
      () =>
          _IndexSource.select('$base.idx', '.gz').$2 == idxStamp &&
          _IndexSource.select('$base.syn', '.dz').$2 == synStamp,
    );
  }

  /// Whether folded lookups can use the on-disk index.
  bool get hasFoldIndex => _fold != null;

  /// Attaches a sidecar published since [open], if it matches these indexes.
  void refreshFoldIndex() {
    if (_fold != null || !_source.unchanged()) return;
    _fold = FoldIndex.open(
      _source.fold,
      _source.idxStamp,
      _source.synStamp,
      _source.rows,
      _index.length,
      4 * max(_index.maxWordBytes, _synonyms?.maxWordBytes ?? 0),
    );
  }

  /// Opens an .ifo set and validates its indexes and definition ranges.
  /// Definition payloads are decoded on demand. The caller owns [close].
  ///
  /// Without a usable sidecar, the default preserves synchronous lookup
  /// behavior by scanning. Workers that build the sidecar asynchronously can
  /// set [scanWithoutFoldIndex] to false to keep only exact lookup available.
  static Dictionary open(File ifo, {bool scanWithoutFoldIndex = true}) {
    try {
      final source = _IndexSource.read(ifo);
      final index = source.index;
      final base = source.base;
      final plain = File('$base.dict');
      final data = _present(plain)
          ? DictionaryData.openPlain(plain)
          : DictionaryData.openDictzip(File('$base.dict.dz'));
      try {
        for (var ordinal = 0; ordinal < index.length; ordinal++) {
          final (:offset, :size) = index.definitionRangeAt(ordinal);
          if (offset > data.length || size > data.length - offset) {
            throw DictionaryFormatException(
              'Definition range outside dictionary data at ordinal $ordinal',
            );
          }
        }
        return Dictionary._(source, data, scanWithoutFoldIndex)
          ..refreshFoldIndex();
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
    final ordinals = exact.isNotEmpty ? exact : _lookupFolded(word);
    return [
      for (final ordinal in ordinals.toList()..sort()) _readEntry(ordinal),
    ];
  }

  Set<int> _lookupFolded(String word) {
    final lower = word.toLowerCase();
    final folded = foldDiacritics(word);
    final indexed = _fromFold((index) {
      final cases = index.lookup(lower, diacritic: false);
      return cases.isNotEmpty ? cases : index.lookup(folded, diacritic: true);
    });
    if (indexed != null) return indexed;
    if (!_scanWithoutFoldIndex) return {};

    final cases = <int>{};
    final accents = <int>{};
    void match(String candidate, int ordinal) {
      if (candidate.toLowerCase() == lower) {
        cases.add(ordinal);
      } else if (foldDiacritics(candidate) == folded) {
        accents.add(ordinal);
      }
    }

    for (var i = 0; i < _index.length; i++) {
      match(_index.headwordAt(i), i);
    }
    final synonyms = _synonyms;
    if (synonyms != null) {
      for (var i = 0; i < synonyms.length; i++) {
        match(synonyms.aliasAt(i), synonyms.ordinalAt(i));
      }
    }
    return cases.isNotEmpty ? cases : accents;
  }

  T? _fromFold<T>(T Function(FoldIndex) read) {
    final fold = _fold;
    if (fold == null) return null;
    try {
      return read(fold);
    } on FormatException {
      // A damaged cache can be replaced independently of the dictionary.
    } on FileSystemException {
      // A failed sidecar read leaves exact lookup available.
    }
    _fold = null;
    fold.close();
    return null;
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

  /// Returns distinct headwords tied for the longest nonempty shared
  /// case- and diacritic-folded prefix, in .idx order.
  List<String> suggest(String query, {int limit = 10}) {
    final folded = foldDiacritics(trimLookupQuery(query));
    if (limit <= 0 || folded.isEmpty) return [];
    final indexed = _fromFold((fold) {
      final matches = SplayTreeMap<int, String>();
      final ordinals = <String, int>{};
      for (final ordinal in fold.suggestions(folded)) {
        if (matches.length == limit && ordinal >= matches.lastKey()!) continue;
        final word = _index.headwordAt(ordinal);
        final previous = ordinals[word];
        if (previous != null) {
          if (previous <= ordinal) continue;
          matches.remove(previous);
        }
        matches[ordinal] = word;
        ordinals[word] = ordinal;
        if (matches.length > limit) {
          ordinals.remove(matches.remove(matches.lastKey()!));
        }
      }
      return matches.values.toList();
    });
    if (indexed != null) return indexed;
    if (!_scanWithoutFoldIndex) return [];

    final key = folded.runes.toList();
    final matches = <String>{};
    var longest = 0;
    for (var i = 0; i < _index.length; i++) {
      final word = _index.headwordAt(i);
      var shared = 0;
      for (final rune in foldDiacritics(word).runes) {
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

  /// Releases the definition file and any open sidecar.
  void close() {
    try {
      _fold?.close();
    } finally {
      _data.close();
    }
  }
}

bool _present(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: false) !=
    FileSystemEntityType.notFound;

final class _IndexSource {
  _IndexSource(
    this.base,
    this.info,
    this.index,
    this.synonyms,
    this.idxStamp,
    this.synStamp,
  );

  final String base;
  final StarDictInfo info;
  final StarDictIndex index;
  final StarDictSynonyms? synonyms;
  final FoldSource idxStamp;
  final FoldSource synStamp;

  File get fold => File('$base.fold');
  int get rows => index.length + (synonyms?.length ?? 0);

  static (File?, FoldSource) select(String path, String compressedSuffix) {
    final plain = File(path);
    if (_present(plain)) return (plain, foldSource(plain, 1));
    final compressed = File('$path$compressedSuffix');
    if (_present(compressed)) return (compressed, foldSource(compressed, 2));
    return (null, foldSource(null, 0));
  }

  bool unchanged() =>
      select('$base.idx', '.gz').$2 == idxStamp &&
      select('$base.syn', '.dz').$2 == synStamp;

  static String baseOf(File ifo) {
    if (!ifo.path.endsWith('.ifo')) {
      throw const DictionaryFormatException('Expected an .ifo file');
    }
    return ifo.path.substring(0, ifo.path.length - '.ifo'.length);
  }

  static void checkSources(StarDictInfo info, File? idx, File? syn) {
    if (idx == null) {
      throw const DictionaryFormatException('Missing .idx or .idx.gz file');
    }
    if (syn == null && (info.synWordCount ?? 0) > 0) {
      throw const DictionaryFormatException('Missing declared .syn file');
    }
  }

  static _IndexSource read(File ifo) {
    final base = baseOf(ifo);
    final info = StarDictInfo.parse(ifo.readAsBytesSync());
    final sequence = info.sameTypeSequence;
    if (sequence != null && !RegExp(r'^[A-Za-z]+$').hasMatch(sequence)) {
      throw const DictionaryFormatException('Invalid sametypesequence');
    }
    final (idx, idxStamp) = select('$base.idx', '.gz');
    final (syn, synStamp) = select('$base.syn', '.dz');
    checkSources(info, idx, syn);
    final index = StarDictIndex.parse(
      idx!.readAsBytesSync(),
      info,
      gzip: idxStamp.kind == 2,
    );
    final synonyms = syn == null
        ? null
        : StarDictSynonyms.parse(
            syn.readAsBytesSync(),
            info,
            gzip: synStamp.kind == 2,
          );
    return _IndexSource(base, info, index, synonyms, idxStamp, synStamp);
  }
}
