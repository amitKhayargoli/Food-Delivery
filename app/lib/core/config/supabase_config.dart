class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static const String baatoApiKey = String.fromEnvironment(
    'BAATO_API_KEY',
    defaultValue: '',
  );

  /// Backend API base URL — set via --dart-define=BACKEND_URL=...
  ///
  /// Default: http://localhost:5000/api
  ///   - Android emulator → run `adb reverse tcp:5000 tcp:5000` first, localhost works
  ///   - Physical device via hotspot → pass `--dart-define=BACKEND_URL=http://<laptop-ip>:5000/api`
  ///   - Emulator without adb reverse → pass `--dart-define=BACKEND_URL=http://10.0.2.2:5000/api`
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:5000/api',
  );

  static const String authRedirectScheme = 'rasoi';
  static const String authRedirectHost = 'login-callback';

  static String get authRedirectUrl =>
      '$authRedirectScheme://$authRedirectHost';

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static bool get isBaatoConfigured => baatoApiKey.isNotEmpty;
}
