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

  static const String authRedirectScheme = 'rasoi';
  static const String authRedirectHost = 'login-callback';

  static String get authRedirectUrl =>
      '$authRedirectScheme://$authRedirectHost';

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static bool get isBaatoConfigured => baatoApiKey.isNotEmpty;
}
