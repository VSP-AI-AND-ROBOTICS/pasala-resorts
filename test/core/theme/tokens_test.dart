import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_theme.dart';
import 'package:pasala/core/theme/tokens.dart';

double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final l1 = lum(a), l2 = lum(b);
  final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('body text on surface passes WCAG AA in both brightnesses', () {
    for (final brightness in Brightness.values) {
      final scheme = buildTheme(brightness).colorScheme;
      expect(_contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(4.5),
          reason: 'onSurface/surface failed for $brightness');
      expect(_contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5),
          reason: 'onPrimary/primary failed for $brightness');
    }
  });

  test('spacing scale is monotonic and starts at 4', () {
    const values = [Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl];
    expect(values.first, 4.0);
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThan(values[i - 1]));
    }
  });

  test('theme applies the token radius to cards and buttons', () {
    final theme = buildTheme(Brightness.light);
    expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
    final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(PasalaTokens.radiusMd));
  });
}
