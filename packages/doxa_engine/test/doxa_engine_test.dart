// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_engine/doxa_engine.dart' as doxa_engine;
import 'package:test/test.dart';

void main() {
  test('library loads', () {
    expect(doxa_engine.packageName, 'doxa_engine');
  });
}
