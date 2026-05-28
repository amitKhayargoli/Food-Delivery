import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../core/services/supabase_client_service.dart';
import '../core/config/supabase_config.dart';

class AuthProvider with ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  
  String? _token;
  String? _role;
  String? _username;
  bool _isLoading = true;

  String? get token => _token;
  String? get role => _role;
  String? get username => _username;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null && !JwtDecoder.isExpired(_token!);

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      _token = await _secureStorage.read(key: 'jwt_token');
      final prefs = await SharedPreferences.getInstance();
      _role = prefs.getString('user_role');
      _username = prefs.getString('username');

      if (_token != null && JwtDecoder.isExpired(_token!)) {
        await logout();
      }
    } catch (e) {
      _token = null;
      _role = null;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> login(String token, String role, String username) async {
    _token = token;
    _role = role;
    _username = username;

    await _secureStorage.write(key: 'jwt_token', value: token);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    await prefs.setString('username', username);

    notifyListeners();
  }

  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      await _googleSignIn.initialize(
        serverClientId: SupabaseConfig.googleWebClientId.isEmpty
            ? null
            : SupabaseConfig.googleWebClientId,
      );

      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null || idToken.isEmpty) {
        return {'success': false, 'error': 'Missing Google ID token'};
      }

      // Exchange Google idToken for a Supabase session (API call, no browser)
      final authResponse = await SupabaseClientService.client.auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
      );

      final sbUser = authResponse.user;
      final session = authResponse.session;

      if (sbUser == null) {
        return {'success': false, 'error': 'Google authentication failed'};
      }

      // Check if user profile exists in the users table
      final rows = await SupabaseClientService.client
          .from('users')
          .select('id, username, phone, role, status')
          .eq('id', sbUser.id)
          .limit(1);

      final hasProfile = rows.isNotEmpty;
      final accessToken = session?.accessToken ?? '';
      final userRole = hasProfile
          ? (rows.first)['role']?.toString() ?? 'USER'
          : 'USER';

      if (hasProfile) {
        // User exists with profile — complete auth
        final displayName = (rows.first)['username']?.toString() ??
            googleUser.displayName ??
            'User';
        await login(accessToken, userRole, displayName);
        return {
          'success': true,
          'requires_profile_completion': false,
        };
      }

      // No profile yet — need phone/username
      return {
        'success': true,
        'requires_profile_completion': true,
        'email': sbUser.email ?? googleUser.email,
        'name': googleUser.displayName ?? 'Google User',
        'token': accessToken,
      };
    } catch (error) {
      debugPrint('Error signing in with Google: $error');
      return {'success': false, 'error': error.toString()};
    }
  }

  Future<void> completeProfile({
    required String phone,
    required String username,
    required String token,
  }) async {
    try {
      // Upsert profile into Supabase users table
      final userId = SupabaseClientService.client.auth.currentUser?.id;
      if (userId != null) {
        await SupabaseClientService.client.from('users').upsert({
          'id': userId,
          'username': username,
          'phone': phone,
          'role': 'USER',
          'status': 'ACTIVE',
        });
      }
      await login(token, 'USER', username);
    } catch (e) {
      debugPrint('Error completing profile: $e');
      await login(token, 'USER', username);
    }
  }

  Future<void> logout() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await SupabaseClientService.client.auth.signOut();
    } catch (_) {}

    _token = null;
    _role = null;
    _username = null;

    await _secureStorage.delete(key: 'jwt_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_role');
    await prefs.remove('username');

    notifyListeners();
  }
}
