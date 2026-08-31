/// Bundled chrome imagery for Pasala Resorts — the brand logo and the
/// property's own photos, used on login/signup/browse/confirmation/empty
/// states. This is separate from `Property.images` (network URLs from the
/// database, rendered by `PropertyMedia`); nothing here ever touches that
/// path.
abstract final class AppAssets {
  static const String logoMark = 'assets/images/logo_mark.jpg';
  static const String heroNightAerial = 'assets/images/hero_night_aerial.png';
  static const String heroDayAerial = 'assets/images/hero_day_aerial.webp';
  static const String cottagesPoolRow = 'assets/images/cottages_pool_row.webp';
  static const String cottagesDallasVegas =
      'assets/images/cottages_dallas_vegas.webp';
  static const String cottagesBostonDetroit =
      'assets/images/cottages_boston_detroit.webp';
  static const String eventStringLights =
      'assets/images/event_string_lights.webp';
  static const String facadeDaytime = 'assets/images/facade_daytime.webp';
  static const String patioFirepitNight =
      'assets/images/patio_firepit_night.webp';
}
