import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../core/services/supabase_client_service.dart';
import '../core/services/push_notification_service.dart';
import '../core/config/supabase_config.dart';
import '../injection_container.dart' as di;

class AuthProvider with ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  
  String? _token;
  String? _role;
  String? _username;
  bool _isLoading = true;
  StreamSubscription<dynamic>? _roleSubscription;
  String? _subscriptionUserId;
  int _subscriptionRetries = 0;
  Timer? _reconnectTimer;
  String? _roleChangeMessage;

  String? get token => _token;
  String? get role => _role;
  String? get username => _username;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null && !JwtDecoder.isExpired(_token!);

  /// Non-null when the role was just changed by a realtime update.
  /// Widgets can read this once and call [clearRoleChangeMessage] to
  /// acknowledge it (e.g. after showing a snackbar).
  String? get roleChangeMessage => _roleChangeMessage;

  void clearRoleChangeMessage() {
    _roleChangeMessage = null;
  }

  /// Start a Supabase Realtime subscription on the current user's row
  /// in the `users` table. When the role changes (e.g. via admin panel),
  /// the app reacts immediately without needing a restart.
  void _startRoleSubscription(String userId) {
    _stopRoleSubscription();
    _subscriptionUserId = userId;
    _subscriptionRetries = 0;

    debugPrint('[RT] ▶ Starting realtime subscription for user: $userId');
    debugPrint('[RT]   └─ current role: $_role, username: $_username');

    _roleSubscription = SupabaseClientService.client
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .listen((List<Map<String, dynamic>> updates) async {
      // Reset retry count on successful data
      _subscriptionRetries = 0;

      debugPrint('[RT] 📦 Realtime update received! count=${updates.length}');
      if (updates.isEmpty) {
        debugPrint('[RT]   └─ updates list is empty, ignoring');
        return;
      }

      debugPrint('[RT]   └─ payload: $updates');

      final latestRole = updates.first['role']?.toString() ?? 'USER';
      final latestUsername =
          updates.first['username']?.toString() ?? 'User';

      debugPrint('[RT]   └─ extracted -> role: $latestRole, username: $latestUsername');
      debugPrint('[RT]   └─ stored   -> role: $_role, username: $_username');

      // Only notify if the role actually changed
      if (_role == latestRole && _username == latestUsername) {
        debugPrint('[RT]   └─ no change detected, skipping');
        return;
      }

      final oldRole = _role;
      _role = latestRole;
      _username = latestUsername;
      debugPrint('[RT] 🚀 Role changed! $oldRole → $latestRole');

      // Build a human-readable message about the role change
      if (oldRole != latestRole) {
        _roleChangeMessage =
            'Your role has been updated to ${_formatRole(latestRole)}.';
        debugPrint('[RT]   └─ roleChangeMessage set: "$_roleChangeMessage"');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', latestRole);
      await prefs.setString('username', latestUsername);
      debugPrint('[RT]   └─ persisted to SharedPreferences');

      notifyListeners();
      debugPrint('[RT]   └─ notifyListeners() called');
    }, onError: (Object error) {
      debugPrint('[RT] ❌ Subscription error: $error');
      _scheduleReconnect();
    }, onDone: () {
      debugPrint('[RT] ⏹ Subscription closed (onDone)');
      _scheduleReconnect();
    });
    debugPrint('[RT]   └─ subscription registered, listening...');
  }

  /// Attempt to re-subscribe with exponential backoff (1s, 2s, 4s, 8s, max 16s).
  void _scheduleReconnect() {
    // Don't reconnect if we've been explicitly stopped
    if (_subscriptionUserId == null) return;

    final delay = Duration(
      seconds: 1 << (_subscriptionRetries < 5 ? _subscriptionRetries : 5),
    );
    _subscriptionRetries++;
    debugPrint('[RT] 🔄 Reconnecting in ${delay.inSeconds}s (attempt $_subscriptionRetries)...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_subscriptionUserId != null) {
        _startRoleSubscription(_subscriptionUserId!);
      }
    });
  }

  /// Format a raw role string (e.g. RESTAURANT_OWNER) for display.
  String _formatRole(String raw) {
    return raw
        .split('_')
        .map((w) => w.isNotEmpty
            ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }

  void _stopRoleSubscription() {
    if (_roleSubscription != null || _reconnectTimer != null) {
      debugPrint('[RT] ⏹ Stopping realtime subscription');
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscriptionUserId = null;
    _subscriptionRetries = 0;
    _roleSubscription?.cancel();
    _roleSubscription = null;
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _stopRoleSubscription();
    super.dispose();
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      _token = await _secureStorage.read(key: 'jwt_token');

      if (_token != null && JwtDecoder.isExpired(_token!)) {
        await logout();
        _isLoading = false;
        notifyListeners();
        return;
      }

      if (_token != null) {
        // Fetch the latest user profile from Supabase so role changes
        // made in the admin panel are reflected immediately.
        final currentUser = SupabaseClientService.client.auth.currentUser;
        if (currentUser != null) {
          final rows = await SupabaseClientService.client
              .from('users')
              .select('username, role')
              .eq('id', currentUser.id)
              .limit(1);

          if (rows.isNotEmpty) {
            final latestRole = (rows.first)['role']?.toString() ?? 'USER';
            final latestUsername =
                (rows.first)['username']?.toString() ?? 'User';

            _role = latestRole;
            _username = latestUsername;

            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_role', latestRole);
            await prefs.setString('username', latestUsername);
          }

          // Start realtime subscription to catch live role changes
          debugPrint('[RT] 🔌 Initializing realtime for user: ${currentUser.id}');
          _startRoleSubscription(currentUser.id);

          // Register FCM device token for push notifications
          if (_token != null) {
            di.sl<PushNotificationService>().init(authToken: _token!);
          }
        }
      }

      // Fallback to cached values if Supabase fetch didn't produce results
      if (_role == null) {
        final prefs = await SharedPreferences.getInstance();
        _role = prefs.getString('user_role');
        _username = prefs.getString('username');
      }
    } catch (e) {
      // If the network call fails, fall back to cached values
      final prefs = await SharedPreferences.getInstance();
      _role = prefs.getString('user_role');
      _username = prefs.getString('username');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> login(String token, String role, String username) async {
    // Decode the JWT to extract the user ID for the role subscription.
    // Supabase access tokens use 'sub' (standard JWT claim), while
    // custom backend JWTs use 'id'.  Fall back to Supabase Auth as a
    // final safety net.
    String? userId;
    try {
      final decoded = JwtDecoder.decode(token);
      userId = (decoded['sub'] ?? decoded['id']) as String?;
    } catch (_) {}

    // If JWT decoding didn't yield a userId, try Supabase Auth directly
    userId ??= SupabaseClientService.client.auth.currentUser?.id;

    _token = token;
    _role = role;
    _username = username;

    await _secureStorage.write(key: 'jwt_token', value: token);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    await prefs.setString('username', username);

    // Start realtime subscription for live role changes
    if (userId != null) {
      debugPrint('[RT] 🔌 Starting realtime subscription after login for user: $userId');
      _startRoleSubscription(userId);
    } else {
      debugPrint('[RT] ⚠️ Could not start realtime subscription — no userId from JWT or Supabase Auth');
    }

    // Register FCM device token for push notifications
    di.sl<PushNotificationService>().init(authToken: token);

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

    debugPrint('[RT] 🚪 Logging out — cleaning up realtime subscription');
    _stopRoleSubscription();

    // Disconnect FCM push notifications
    di.sl<PushNotificationService>().dispose();

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
