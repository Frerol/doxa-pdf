// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_pdf/features/library/folder_page.dart';
import 'package:doxa_platform/doxa_platform.dart';
import 'package:flutter_test/flutter_test.dart';

PlatformFolderEntry entry(
  String name, {
  bool dir = false,
  int? size,
  int? modified,
}) => PlatformFolderEntry(
  documentId: name,
  uri: 'content://t/tree/1/document/$name',
  name: name,
  isDirectory: dir,
  size: size,
  lastModified: modified,
);

void main() {
  group('folder order (FR-FILE-006)', () {
    final entries = [
      entry('zeta.pdf', size: 10, modified: 300),
      entry('Álgebra.pdf', size: 30, modified: 100),
      entry('Notes', dir: true, modified: 50),
      entry('beta.pdf', modified: 200),
      entry('Articles', dir: true, modified: 400),
    ];
    List<String> names(FolderSort sort) => [
      for (final e in sortEntries(entries, sort)) e.name,
    ];

    test('by name: folders first, then ignoring case and accents', () {
      expect(names(FolderSort.name), [
        'Articles',
        'Notes',
        'Álgebra.pdf',
        'beta.pdf',
        'zeta.pdf',
      ]);
    });

    test('by date: newest first, folders still first', () {
      expect(names(FolderSort.modified), [
        'Articles',
        'Notes',
        'zeta.pdf',
        'beta.pdf',
        'Álgebra.pdf',
      ]);
    });

    test('by size: largest first, unknown sizes last', () {
      expect(names(FolderSort.size).skip(2), [
        'Álgebra.pdf',
        'zeta.pdf',
        'beta.pdf',
      ]);
    });
  });

  test('file sizes use the locale decimal separator', () {
    expect(formatFileSize(2345678, 'pt'), '2,3 MB');
    expect(formatFileSize(2345678, 'en'), '2.3 MB');
    expect(formatFileSize(999, 'en'), '999 B');
  });
}
