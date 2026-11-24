// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_ink/doxa_ink.dart' as doxa_ink;
import 'package:test/test.dart';

void main() {
  test('library loads', () {
    expect(doxa_ink.packageName, 'doxa_ink');
  });
}
