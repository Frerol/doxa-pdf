// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:test/test.dart';

/// Enforces the dependency rule from docs/plan/03-architecture.md §2:
/// `doxa_core` stays pure Dart.
void main() {
  test('doxa_core does not depend on Flutter', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('sdk: flutter')));
    expect(
      pubspec,
      isNot(matches(RegExp(r'^\s+flutter\w*:', multiLine: true))),
    );
  });

  test('doxa_core does not import Flutter or dart:ui', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in sources) {
      final text = file.readAsStringSync();
      expect(text, isNot(contains('package:flutter')), reason: file.path);
      expect(text, isNot(contains("'dart:ui'")), reason: file.path);
    }
  });
}
