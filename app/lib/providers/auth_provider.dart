import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class AuthProvider with ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
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
