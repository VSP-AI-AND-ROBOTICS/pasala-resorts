class AppConfig {
  static String supabaseUrl = const String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xyzresorthub.supabase.co',
  );

  static String supabaseAnonKey = const String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh5enJlc29ydGh1YiIsInJvbGUiOiJhbW9uIiwiaWF0IjoxNzA0MDY3MjAwLCJleHAiOjIwMTk2NDMyMDB9.sample',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseUrl != 'https://xyzresorthub.supabase.co' &&
      supabaseAnonKey.isNotEmpty;
}
