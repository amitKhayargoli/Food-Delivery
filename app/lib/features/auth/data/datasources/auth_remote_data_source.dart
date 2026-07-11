import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/services/supabase_client_service.dart';
import '../../../../core/errors/failures.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> login(String identifier, String password);
  Future<UserModel> register({
    required String username,
    required String email,
    required String phone,
    required String password,
  });
  Future<UserModel> signInWithGoogle();
  Future<void> logout();
  Stream<UserModel?> get onAuthStateChanged;
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final SupabaseClient Function() _clientProvider;
  final GoogleSignIn _googleSignIn;
  final bool Function()? _configuredCheck;
  final Future<AuthResponse> Function({
    required String idToken,
    String? accessToken,
  })? _signInWithIdToken;
  final Future<Map<String, dynamic>?> Function(String userId)? _getProfileByUserId;
  final Future<void> Function(Map<String, dynamic> profile)? _upsertProfile;

  SupabaseClient get client => _clientProvider();

  AuthRemoteDataSourceImpl(
    this._clientProvider,
    this._googleSignIn, {
    bool Function()? configuredCheck,
    Future<AuthResponse> Function({
      required String idToken,
      String? accessToken,
    })? signInWithIdToken,
    Future<Map<String, dynamic>?> Function(String userId)? getProfileByUserId,
    Future<void> Function(Map<String, dynamic> profile)? upsertProfile,
  })  : _configuredCheck = configuredCheck,
        _signInWithIdToken = signInWithIdToken,
        _getProfileByUserId = getProfileByUserId,
        _upsertProfile = upsertProfile;

  Future<Map<String, dynamic>?> _getProfile(String userId) async {
    final rows = (await client
        .from('users')
        .select('id, username, email, phone, role, status')
        .eq('id', userId)
        .limit(1)) as List<dynamic>;

    if (rows.isNotEmpty) {
      return rows.first as Map<String, dynamic>;
    }

    return null;
  }

  Future<void> _ensureConfigured() async {
    final isConfigured = _configuredCheck?.call() ??
        (SupabaseClientService.isReady && SupabaseConfig.isConfigured);

    if (!isConfigured) {
      throw const ServerFailure(
        'Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }
  }

  Future<void> _upsertUserProfile(Map<String, dynamic> profile) async {
    if (_upsertProfile != null) {
      await _upsertProfile(profile);
      return;
    }

    await client.from('users').upsert(profile);
  }

  Future<AuthResponse> _exchangeGoogleToken({
    required String idToken,
    String? accessToken,
  }) {
    if (_signInWithIdToken != null) {
      return _signInWithIdToken(idToken: idToken, accessToken: accessToken);
    }

    return client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>?> _loadProfile(String userId) {
    if (_getProfileByUserId != null) {
      return _getProfileByUserId(userId);
    }

    return _getProfile(userId);
  }

  @override
  Future<UserModel> login(String identifier, String password) async {
    await _ensureConfigured();

    try {
      String email = identifier;

      if (!identifier.contains('@')) {
        final rows = (await client
            .from('users')
            .select('email')
            .eq('phone', identifier)
            .limit(1)) as List<dynamic>;

        if (rows.isNotEmpty) {
          email = ((rows.first as Map<String, dynamic>)['email'] ?? '').toString();
        }

        if (email.isEmpty || !email.contains('@')) {
          throw const ServerFailure('No account found for this phone number');
        }
      }

      final authResponse = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final session = authResponse.session;
      final user = authResponse.user;

      if (user == null) {
        throw const ServerFailure('Authentication failed');
      }

      final profile = await _getProfile(user.id);

      return UserModel.fromSupabaseProfile(
        authUserId: user.id,
        authEmail: user.email ?? email,
        accessToken: session?.accessToken,
        profile: profile,
      );
    } on AuthException catch (e) {
      throw ServerFailure(e.message);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<UserModel> register({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) async {
    await _ensureConfigured();

    try {
      final authResponse = await client.auth.signUp(
        email: email,
        password: password,
        data: {
          'username': username,
          'phone': phone,
          'role': 'CUSTOMER',
        },
      );

      final user = authResponse.user;
      if (user == null) {
        throw const ServerFailure('Registration failed');
      }

      await client.from('users').upsert({
        'id': user.id,
        'username': username,
        'email': email,
        'phone': phone,
        'role': 'CUSTOMER',
        'status': 'ACTIVE',
      });

      final profile = await _getProfile(user.id);

      return UserModel.fromSupabaseProfile(
        authUserId: user.id,
        authEmail: user.email ?? email,
        accessToken: authResponse.session?.accessToken,
        profile: profile,
      );
    } on AuthException catch (e) {
      throw ServerFailure(e.message);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<UserModel> signInWithGoogle() async {
    await _ensureConfigured();

    try {
      await _googleSignIn.initialize(
        serverClientId: SupabaseConfig.googleWebClientId.isEmpty
            ? null
            : SupabaseConfig.googleWebClientId,
      );

      final account = await _googleSignIn.authenticate();

      final googleAuth = account.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const ServerFailure('Missing Google ID token');
      }

      final authResponse = await _exchangeGoogleToken(
        idToken: idToken,
      );

      final user = authResponse.user;
      final session = authResponse.session;

      if (user == null) {
        throw const ServerFailure('Google login did not complete');
      }

      final existingProfile = await _loadProfile(user.id);
      if (existingProfile == null) {
        await _upsertUserProfile({
          'id': user.id,
          'username': user.userMetadata?['name']?.toString() ??
              user.email?.split('@').first ??
              'user_${user.id.substring(0, 8)}',
          'email': user.email,
          'phone': '',
          'role': 'CUSTOMER',
          'status': 'ACTIVE',
        });
      }

      final profile = await _loadProfile(user.id);

      return UserModel.fromSupabaseProfile(
        authUserId: user.id,
        authEmail: user.email ?? '',
        accessToken: session?.accessToken,
        profile: profile,
      );
    } on AuthException catch (e) {
      throw ServerFailure(e.message);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> logout() async {
    await _ensureConfigured();
    await client.auth.signOut();
  }

  @override
  Stream<UserModel?> get onAuthStateChanged {
    return client.auth.onAuthStateChange.map((data) {
      final session = data.session;
      final user = session?.user;
      if (user != null) {
        return UserModel.fromSupabaseProfile(
          authUserId: user.id,
          authEmail: user.email ?? '',
          accessToken: session?.accessToken,
          profile: null,
        );
      }
      return null;
    });
  }
}
