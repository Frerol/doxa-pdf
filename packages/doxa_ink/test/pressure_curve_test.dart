// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_ink/doxa_ink.dart';
import 'package:test/test.dart';

void main() {
  group('FR-INK-002 pressure', () {
    test('endpoints and default gamma', () {
      final curve = PressureCurve();
      expect(curve.map(0), 0);
      expect(curve.map(1), 1);
      expect(curve.map(0.4), 0.4);
    });
    test('gamma response and monotonicity', () {
      for (final gamma in [0.3, 1.0, 2.0, 3.0]) {
        final curve = PressureCurve(gamma: gamma);
        for (var i = 1; i <= 100; i++) {
          expect(curve.map(i / 100), greaterThan(curve.map((i - 1) / 100)));
        }
      }
      expect(PressureCurve(gamma: 2).map(0.5), 0.25);
    });
    test('pressure clamps and NaN uses midpoint', () {
      final curve = PressureCurve();
      expect(curve.map(-1), 0);
      expect(curve.map(double.infinity), 1);
      expect(curve.map(double.nan), 0.5);
    });
    test('gamma clamps including NaN', () {
      expect(PressureCurve(gamma: -1).gamma, 0.3);
      expect(PressureCurve(gamma: 9).gamma, 3);
      expect(PressureCurve(gamma: double.nan).gamma, 0.5);
    });
    test('linear ignores pressure', () {
      for (final p in [-1.0, 0.0, 1.0, double.nan]) {
        expect(const PressureCurve.linear().map(p), 0.5);
      }
    });
    test('radius formula and input clamping', () {
      expect(strokeRadius(2, 0), 0.35);
      expect(strokeRadius(2, 1), closeTo(1.65, 1e-12));
      expect(strokeRadius(2, double.nan), 1);
      expect(strokeRadius(2, -1), 0.35);
      expect(strokeRadius(2, 2), closeTo(1.65, 1e-12));
      expect(strokeRadius(-2, 1), 0);
      expect(strokeRadius(double.nan, 0.5), 0.25);
    });
  });
}
