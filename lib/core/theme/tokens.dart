import 'package:flutter/material.dart';

export 'spacing.dart';

/// Design tokens for Pasala Resorts.
///
/// The palette is fresh and land-facing rather than corporate blue: an
/// emerald green for primary actions and highlights, and a soft mint
/// surface (deep ink in dark mode) that photographs of the property sit on
/// without fighting them.
abstract final class PasalaTokens {
  static const Color seed = Color(0xFF059669);
  static const Color accent = Color(0xFF10B981);
  static const Color mintBackgroundLight = Color(0xFFEDF6F2);
  static const Color darkCanvas = Color(0xFF0B1118);

  static const double displayLetterSpacing = -0.8;
  static const FontWeight displayWeight = FontWeight.w700;

  /// The single width breakpoint the app treats as "wide" (desktop/tablet
  /// landscape vs. phone) — shared by `AppShell`'s rail/bottom-bar switch
  /// and `BrowseScreen`'s grid/list switch so the two can never disagree.
  static const double wideBreakpoint = 840;

  static const double radiusSm = 8;
  static const double radiusMd = 16;
  static const double radiusLg = 28;

  static const Duration motionFast = Duration(milliseconds: 150);
  static const Duration motionBase = Duration(milliseconds: 250);

  /// Minimum interactive size, per WCAG 2.5.5 and Material guidance.
  static const double minTapTarget = 48;
}
