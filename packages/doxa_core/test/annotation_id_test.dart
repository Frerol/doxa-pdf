// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:doxa_core/doxa_core.dart';
import 'package:test/test.dart';

void main() {
  test('T-02 UUID v4 format, version and variant', () {
    for (var i = 0; i < 100; i++) {
      final id = AnnotationId.generate();
      expect(id.length, 36);
      expect(id, id.toLowerCase());
      expect(id[14], '4');
      expect('89ab', contains(id[19]));
      expect(AnnotationId.isValid(id), isTrue);
    }
  });
  test('T-02 10000 identifiers are unique', () {
    expect({
      for (var i = 0; i < 10000; i++) AnnotationId.generate(),
    }, hasLength(10000));
  });
  test('T-02 validator accepts v4 and rejects malformed identifiers', () {
    const valid = '01234567-89ab-4cde-8fab-0123456789ab';
    expect(AnnotationId.isValid(valid), isTrue);
    for (final invalid in [
      '',
      valid.toUpperCase(),
      '${valid}x',
      '$valid\n',
      valid.replaceFirst('4cde', '1cde'),
      valid.replaceFirst('8fab', '7fab'),
      valid.replaceAll('-', ''),
      valid.replaceFirst('0', 'g'),
    ]) {
      expect(AnnotationId.isValid(invalid), isFalse, reason: invalid);
    }
  });
}
