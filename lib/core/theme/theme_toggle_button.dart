import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_mode_provider.dart';

/// A reusable sun/moon icon button that flips between light and dark. From
/// [ThemeMode.system] it switches to the opposite of whatever brightness is
/// currently in effect (via [MediaQuery]'s platform brightness), so the
/// first tap always visibly changes something rather than silently pinning
/// the mode to whatever "system" already resolved to.
///
/// Icon and tooltip reflect the mode this button would switch *to* -- a
/// moon in light mode ("Switch to dark mode"), a sun in dark mode ("Switch
/// to light mode") -- matching the effective brightness `MaterialApp`
/// itself is currently rendering with, whether that came from an explicit
/// choice or from `ThemeMode.system`.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final effectiveBrightness = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };
    final isDark = effectiveBrightness == Brightness.dark;

    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () =>
          ref.read(themeModeProvider.notifier).toggle(effectiveBrightness),
    );
  }
}
