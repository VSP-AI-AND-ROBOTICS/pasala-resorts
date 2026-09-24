import 'package:shared_preferences/shared_preferences.dart';

import 'place_label.dart';

/// Injectable clock, matching the `now`-parameter pattern used by
/// `greetingFor`/`greetingLine` -- lets tests fast-forward "time" without
/// a real 24h wait.
typedef Clock = DateTime Function();

/// Caches the browse hero's resolved [PlaceLabel] in `shared_preferences`
/// for [validFor] (24h) so `LocationService` doesn't ask the OS/Nominatim
/// again on every app open. A pure synchronous [read] over the already-
/// loaded `SharedPreferences` instance (same pattern as
/// `core/current_resort.dart`) keeps the cache logic unit-testable without
/// pumping a widget.
class LocationCache {
  LocationCache(this._prefs, {Clock clock = DateTime.now}) : _clock = clock;

  final SharedPreferences _prefs;
  final Clock _clock;

  static const validFor = Duration(hours: 24);

  static const _localityKey = 'location_cache_locality';
  static const _countryKey = 'location_cache_country';
  static const _cachedAtKey = 'location_cache_cached_at_ms';

  /// The cached label, or null when nothing is cached or the cached entry
  /// is older than [validFor].
  PlaceLabel? read() {
    final locality = _prefs.getString(_localityKey);
    final country = _prefs.getString(_countryKey);
    final cachedAtMs = _prefs.getInt(_cachedAtKey);
    if (locality == null || country == null || cachedAtMs == null) {
      return null;
    }

    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
    if (_clock().difference(cachedAt) > validFor) return null;

    return PlaceLabel(locality: locality, country: country);
  }

  /// Persists [label] with the current time (per [clock]) as its cache
  /// timestamp.
  Future<void> write(PlaceLabel label) async {
    await _prefs.setString(_localityKey, label.locality);
    await _prefs.setString(_countryKey, label.country);
    await _prefs.setInt(_cachedAtKey, _clock().millisecondsSinceEpoch);
  }
}
