import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/app_theme.dart';
import 'package:pasala/core/theme/tokens.dart';

void main() {
  test('wideBreakpoint matches the layout breakpoint used across the app', () {
    expect(PasalaTokens.wideBreakpoint, 840.0);
  });

  test('headline styles use the display weight and tracking tokens', () {
    for (final brightness in Brightness.values) {
      final textTheme = buildTheme(brightness).textTheme;
      expect(textTheme.headlineMedium!.fontWeight, PasalaTokens.displayWeight);
      expect(
        textTheme.headlineMedium!.letterSpacing,
        PasalaTokens.displayLetterSpacing,
      );
      expect(textTheme.headlineSmall!.fontWeight, PasalaTokens.displayWeight);
      expect(
        textTheme.headlineSmall!.letterSpacing,
        PasalaTokens.displayLetterSpacing,
      );
    }
  });
}
