import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Always fails every call -- simulates SharedPreferences being unavailable
/// (denied storage permission, corrupted store, ...) so the notifier's
/// try/catch fallback can be exercised without a real platform channel.
class _ThrowingSharedPreferencesStore extends SharedPreferencesStorePlatform {
  @override
  Future<bool> clear() => throw PlatformException(code: 'boom');

  @override
  Future<Map<String, Object>> getAll() => throw PlatformException(code: 'boom');

  @override
  Future<bool> remove(String key) => throw PlatformException(code: 'boom');

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      throw PlatformException(code: 'boom');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to ThemeMode.system', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('setMode persists the choice and a fresh notifier reloads it', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    expect(container.read(themeModeProvider), ThemeMode.dark);

    // A brand-new container (e.g. a fresh app start) must read the
    // persisted choice back once its async load completes.
    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    expect(reloaded.read(themeModeProvider), ThemeMode.system);
    await Future<void>.delayed(Duration.zero);
    expect(reloaded.read(themeModeProvider), ThemeMode.dark);
  });

  test('toggle flips light<->dark, and from system flips the opposite of '
      'the current effective brightness', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(themeModeProvider.notifier).toggle(Brightness.light);
    expect(container.read(themeModeProvider), ThemeMode.dark);

    await container.read(themeModeProvider.notifier).toggle(Brightness.dark);
    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  test(
    'a SharedPreferences failure on load falls back to ThemeMode.system',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance =
          _ThrowingSharedPreferencesStore();
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(themeModeProvider), ThemeMode.system);
    },
  );

  test('a SharedPreferences failure on setMode still updates in-memory '
      'state', () async {
    final original = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = _ThrowingSharedPreferencesStore();
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
