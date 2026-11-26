// SPDX-License-Identifier: GPL-3.0-or-later

final _surroundingWhitespaceOrPunctuation = RegExp(
  r'^[\p{White_Space}\p{P}\uFEFF]+|[\p{White_Space}\p{P}\uFEFF]+$',
  unicode: true,
);

String trimLookupQuery(String query) =>
    query.replaceAll(_surroundingWhitespaceOrPunctuation, '');

/// Latin-1 Supplement and Latin Extended-A canonical bases (Unicode NFD).
/// The combining suffixes are omitted because folding discards them anyway.
const _latinGroups = {
  'a': 'ÀÁÂÃÄÅàáâãäåĀāĂăĄą',
  'c': 'ÇçĆćĈĉĊċČč',
  'd': 'Ďď',
  'e': 'ÈÉÊËèéêëĒēĔĕĖėĘęĚě',
  'g': 'ĜĝĞğĠġĢģ',
  'h': 'Ĥĥ',
  'i': 'ÌÍÎÏìíîïĨĩĪīĬĭĮįİ',
  'j': 'Ĵĵ',
  'k': 'Ķķ',
  'l': 'ĹĺĻļĽľ',
  'n': 'ÑñŃńŅņŇň',
  'o': 'ÒÓÔÕÖòóôõöŌōŎŏŐő',
  'r': 'ŔŕŖŗŘř',
  's': 'ŚśŜŝŞşŠš',
  't': 'ŢţŤť',
  'u': 'ÙÚÛÜùúûüŨũŪūŬŭŮůŰűŲų',
  'w': 'Ŵŵ',
  'y': 'ÝýÿŶŷŸ',
  'z': 'ŹźŻżŽž',
};

final _latinBases = {
  for (final group in _latinGroups.entries)
    for (final rune in group.value.runes) rune: group.key,
};

/// [word] lower-cased, with Latin diacritics and combining marks removed:
/// "Ação" and "acao" fold to the same key.
String foldDiacritics(String word) {
  final folded = StringBuffer();
  for (final rune in word.runes) {
    if (rune >= 0x0300 && rune <= 0x036f) continue;
    final base = _latinBases[rune];
    if (base != null) {
      folded.write(base);
    } else {
      folded.writeCharCode(rune);
    }
  }
  return folded.toString().toLowerCase();
}
