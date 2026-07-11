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
  /// Default is 192.168.1.81:5000 (your LAN IP).
  /// If Waydroid ever uses emulated NAT instead of bridged networking,
  /// change to 10.0.2.2:5000.
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://192.168.1.81:5000/api',
  );

  static const String authRedirectScheme = 'rasoi';
  static const String authRedirectHost = 'login-callback';

  static String get authRedirectUrl =>
      '$authRedirectScheme://$authRedirectHost';

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static bool get isBaatoConfigured => baatoApiKey.isNotEmpty;
}
