import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/theme_mode_provider.dart';
import 'package:pasala/core/theme/theme_toggle_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _appFor({required ThemeMode overrideMode}) {
  return ProviderScope(
    overrides: [
      themeModeProvider.overrideWith(() => _FixedThemeMode(overrideMode)),
    ],
    child: MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: overrideMode,
      home: const Scaffold(body: ThemeToggleButton()),
    ),
  );
}

/// A [ThemeModeNotifier] fixed to whatever mode the test starts with, so
/// widget tests can assert on the button's tooltip/icon for a known
/// starting mode without going through real `SharedPreferences` timing.
class _FixedThemeMode extends ThemeModeNotifier {
  _FixedThemeMode(this._initial);
  final ThemeMode _initial;

  @override
  ThemeMode build() => _initial;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows a moon icon with a "Switch to dark mode" tooltip in '
      'light mode', (tester) async {
    await tester.pumpWidget(_appFor(overrideMode: ThemeMode.light));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    expect(find.byTooltip('Switch to dark mode'), findsOneWidget);
  });

  testWidgets('shows a sun icon with a "Switch to light mode" tooltip in '
      'dark mode', (tester) async {
    await tester.pumpWidget(_appFor(overrideMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    expect(find.byTooltip('Switch to light mode'), findsOneWidget);
  });

  testWidgets('tapping the button flips the mode from light to dark', (
    tester,
  ) async {
    await tester.pumpWidget(_appFor(overrideMode: ThemeMode.light));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    expect(find.byTooltip('Switch to light mode'), findsOneWidget);
  });
}
