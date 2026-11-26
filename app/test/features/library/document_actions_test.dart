// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_pdf/features/library/document_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rename target (FR-FILE-011)', () {
    test('keeps the .pdf extension the user left out', () {
      expect(renameTarget('Calculus II', 'Calculus.pdf'), 'Calculus II.pdf');
      expect(renameTarget(' Notes.PDF ', 'Calculus.pdf'), 'Notes.PDF');
    });

    test('adds no extension the file did not have', () {
      expect(renameTarget('Book', 'Book (scan)'), 'Book');
    });

    test('refuses names a file cannot have, and unchanged names', () {
      for (final typed in [
        '',
        '   ',
        '.',
        '..',
        'a/b',
        'a\u0000b',
        'Calculus',
      ]) {
        expect(renameTarget(typed, 'Calculus.pdf'), isNull, reason: typed);
      }
    });
  });
}
