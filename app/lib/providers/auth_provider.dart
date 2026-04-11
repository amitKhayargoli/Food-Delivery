import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthProvider with ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  
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
        await logout(); // Clear expired token
      }
    } catch (e) {
      // Handle storage errors gracefully
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
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return {'success': false, 'error': 'User canceled the sign-in'};
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken != null) {
        // Here you would typically send the idToken to your backend API
        // For now, we simulate that a new user needs profile completion
        // Set to true to simulate a new Google sign-in requiring phone and username
        bool requiresProfileCompletion = true; 

        if (requiresProfileCompletion) {
          return {
            'success': true,
            'requires_profile_completion': true,
            'email': googleUser.email,
            'name': googleUser.displayName ?? 'Google User',
            'token': idToken,
          };
        } else {
          await login(idToken, 'USER', googleUser.displayName ?? 'Google User');
          return {
            'success': true,
            'requires_profile_completion': false,
          };
        }
      }
      return {'success': false, 'error': 'Token is null'};
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
    // Ideally send the phone and username along with the token to backend
    // For now, mock a successful login
    await login(token, 'USER', username);
  }

  Future<void> logout() async {
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
