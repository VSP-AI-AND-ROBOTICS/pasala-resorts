import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'theme_mode';

ThemeMode _parseThemeMode(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

String _themeModeString(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

/// The user's light/dark/system preference, persisted to
/// `shared_preferences` under 'theme_mode' ('system' | 'light' | 'dark';
/// default 'system'). [build] resolves synchronously to [ThemeMode.system]
/// on the very first build (a cold app hasn't read storage yet) and kicks
/// off the async load in the background, mirroring `CurrentResort`'s own
/// cold-start-then-reconcile shape. Every `SharedPreferences` access is
/// wrapped in try/catch so a storage failure (denied permission, corrupted
/// store, ...) falls back to [ThemeMode.system] instead of crashing app
/// start or losing the toggle.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  /// Bumped by every call that decides [state] on its own authority
  /// ([setMode] and each fresh [_load] call) -- mirrors
  /// `CurrentResort._generation`: a stale async continuation checks this
  /// before applying its result, so a `setMode` right after a cold-start
  /// `build()` can't be clobbered a moment later by that first load
  /// finally resolving.
  int _generation = 0;

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final generation = _generation;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation != _generation) return;
      state = _parseThemeMode(prefs.getString(_themeModeKey));
    } catch (_) {
      if (generation == _generation) state = ThemeMode.system;
    }
  }

  /// Sets the preference immediately (so the UI reflects it without
  /// waiting on storage) and persists it. A persistence failure is
  /// swallowed -- the in-memory [state] still reflects the choice for the
  /// rest of this session, there's just no useful recovery action to take
  /// on a write failure.
  Future<void> setMode(ThemeMode mode) async {
    _generation++;
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, _themeModeString(mode));
    } catch (_) {
      // Persistence failed; in-memory state already reflects the choice.
    }
  }

  /// Toggles light<->dark. From [ThemeMode.system], flips to the opposite
  /// of [effectiveBrightness] (the platform brightness currently in
  /// effect), so the very first tap always visibly changes something.
  Future<void> toggle(Brightness effectiveBrightness) => setMode(
    effectiveBrightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
  );
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
