import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../core/services/api_service.dart';
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
  sb.RealtimeChannel? _realtimeChannel;
  String? _subscriptionUserId;
  int _subscriptionRetries = 0;
  Timer? _reconnectTimer;
  Timer? _pollTimer;
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
  /// in the `users` table. Uses `onPostgresChanges()` which reliably
  /// fires on UPDATE events, unlike `.stream()` which only fetches
  /// initial data via HTTP.
  void _startRoleSubscription(String userId) {
    _stopRoleSubscription();
    _subscriptionUserId = userId;
    _subscriptionRetries = 0;

    final channelName = 'user-role-$userId';
    debugPrint('[RT] ▶ [${DateTime.now().toIso8601String()}] Starting realtime channel "$channelName"');
    debugPrint('[RT]   └─ current role: $_role, username: $_username');

    // Subscribe to postgres_changes on the users table, filtered to this user.
    // The 'UPDATE' event fires when the admin changes the role.
    _realtimeChannel = SupabaseClientService.client.channel(channelName);

    _realtimeChannel!.onPostgresChanges(
      event: sb.PostgresChangeEvent.update,
      schema: 'public',
      table: 'users',
      callback: (payload) {
        _subscriptionRetries = 0;

        final newRecord = payload.newRecord;
        final recordId = newRecord['id']?.toString();

        // Ignore updates to other users' rows
        if (recordId != userId) {
          return;
        }

        final latestRole = newRecord['role']?.toString() ?? 'USER';
        final latestUsername = newRecord['username']?.toString() ?? 'User';

        debugPrint('[RT] 📦 [${DateTime.now().toIso8601String()}] Realtime UPDATE received');
        debugPrint('[RT]   └─ extracted -> role: $latestRole, username: $latestUsername');
        debugPrint('[RT]   └─ stored   -> role: $_role, username: $_username');

        // Only notify if the role actually changed
        if (_role == latestRole && _username == latestUsername) {
          debugPrint('[RT]   └─ no change detected, skipping');
          return;
        }

        _onRoleChanged(latestRole, latestUsername);
      },
    );

    _realtimeChannel!.subscribe((status, [error]) async {
      debugPrint('[RT] 📡 Channel status: $status');
      if (error != null) {
        debugPrint('[RT] ❌ Subscribe error: $error');
      }
      // Only reconnect on actual errors (channelError, timedOut).
      // We IGNORE 'closed' because removeChannel() in _stopRoleSubscription
      // also fires this callback — handling it would race with the normal
      // subscription lifecycle and create a cascade of duplicate channels.
      if (status == sb.RealtimeSubscribeStatus.channelError ||
          status == sb.RealtimeSubscribeStatus.timedOut) {
        debugPrint('[RT] ⏹ Channel error — scheduling reconnect');
        _scheduleReconnect();
      }
    });

    debugPrint('[RT]   └─ channel subscribed, listening for UPDATE events...');
  }



  /// Handle a detected role change from either Realtime or polling.
  /// Updates internal state, persists to SharedPreferences, and notifies listeners.
  /// When Realtime works, this delivers INSTANT detection.
  /// The 20s poll is the reliable fallback.
  void _onRoleChanged(String latestRole, String latestUsername) {
    final oldRole = _role;
    _role = latestRole;
    _username = latestUsername;

    debugPrint('[RT] 🚀 [${DateTime.now().toIso8601String()}] Role changed! $oldRole → $latestRole');

    if (oldRole != latestRole) {
      _roleChangeMessage =
          'Your role has been updated to ${_formatRole(latestRole)}.';
      debugPrint('[RT]   └─ roleChangeMessage set: "$_roleChangeMessage"');
    }

    // Persist asynchronously (fire-and-forget)
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('user_role', latestRole);
      prefs.setString('username', latestUsername);
    });

    notifyListeners();
    debugPrint('[RT]   └─ notifyListeners() called');
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
    if (_realtimeChannel != null || _reconnectTimer != null) {
      debugPrint('[RT] ⏹ Stopping realtime subscription');
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscriptionUserId = null;
    _subscriptionRetries = 0;
    if (_realtimeChannel != null) {
      SupabaseClientService.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  /// Periodically fetch the user's role from Supabase as a reliable fallback.
  /// Realtime is the preferred (instant) mechanism, but polling ensures we
  /// never miss a role change even if the WebSocket silently drops.
  /// Uses a recursive timer so the next tick only fires after the
  /// previous one completes — prevents concurrent requests.
  /// The 20s interval gives a good balance of responsiveness and API load.
  void _startPolling(String userId) {
    _pollTimer?.cancel();
    _pollTimer = null;
    debugPrint('[RT] 📟 Starting poll fallback (every 20s) for user: $userId');

    _schedulePollTick(userId);
  }

  void _schedulePollTick(String userId) {
    _pollTimer?.cancel();
    late final Timer timer;
    timer = Timer(const Duration(seconds: 20), () async {
      if (_token == null || _subscriptionUserId == null) return;

      try {
        final rows = await SupabaseClientService.client
            .from('users')
            .select('role, username')
            .eq('id', userId)
            .limit(1);

        if (rows.isEmpty) {
          _scheduleNextIfStillActive(userId, timer);
          return;
        }

        final latestRole = (rows.first)['role']?.toString() ?? 'USER';
        final latestUsername = (rows.first)['username']?.toString() ?? 'User';

        if (_role != latestRole || _username != latestUsername) {
          debugPrint('[RT] 📟 [${DateTime.now().toIso8601String()}] Poll detected role change! $_role → $latestRole');

          final oldRole = _role;
          _role = latestRole;
          _username = latestUsername;

          if (oldRole != latestRole) {
            _roleChangeMessage =
                'Your role has been updated to ${_formatRole(latestRole)}.';
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_role', latestRole);
          await prefs.setString('username', latestUsername);

          notifyListeners();
        }
      } catch (e) {
        debugPrint('[RT] 📟 Poll error: $e');
      }

      // Schedule the next tick only if this tick's timer is still current
      // (guards against stale callbacks after _startPolling is called again)
      _scheduleNextIfStillActive(userId, timer);
    });
    _pollTimer = timer;
  }

  /// Schedule the next poll tick, but only if [timer] is still the
  /// active timer (not replaced by a new [startPolling] call).
  void _scheduleNextIfStillActive(String userId, Timer timer) {
    if (_token != null &&
        _subscriptionUserId != null &&
        identical(_pollTimer, timer)) {
      _schedulePollTick(userId);
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
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

          // Start realtime subscription + poll fallback to catch live role changes
          debugPrint('[RT] 🔌 Initializing realtime for user: ${currentUser.id}');
          _startRoleSubscription(currentUser.id);
          _startPolling(currentUser.id);

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

    // Start realtime subscription + poll fallback for live role changes
    if (userId != null) {
      debugPrint('[RT] 🔌 Starting realtime subscription after login for user: $userId');
      _startRoleSubscription(userId);
      _startPolling(userId);
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

      // Step 1: Exchange Google idToken for a Supabase session
      // (needed for Realtime subscriptions, FCM, and profile lookup)
      final authResponse = await SupabaseClientService.client.auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
      );

      final sbUser = authResponse.user;
      if (sbUser == null) {
        return {'success': false, 'error': 'Google authentication failed'};
      }

      // Step 2: Exchange the same idToken for a backend-issued JWT
      // (the custom backend signs its own JWTs with JWT_SECRET, so upload
      //  and submission endpoints can verify them)
      final api = di.sl<ApiService>();
      GoogleAuthResponse googleAuthResponse;
      try {
        googleAuthResponse = await api.googleAuth(idToken: idToken);
      } on ApiException catch (e) {
        return {'success': false, 'error': e.message};
      }

      // Determine if the user has a full profile (non-temp phone)
      final String backendToken;
      final bool requiresProfileCompletion;

      final tempToken = googleAuthResponse.tempToken;
      if (tempToken != null && tempToken.isNotEmpty) {
        // Backend says profile is incomplete — use the temp token
        backendToken = tempToken;
        requiresProfileCompletion = true;
      } else if (googleAuthResponse.token.isNotEmpty) {
        // Full auth — use the full backend JWT
        backendToken = googleAuthResponse.token;
        requiresProfileCompletion = false;
      } else {
        return {'success': false, 'error': 'Failed to authenticate with server'};
      }

      // Check Supabase users table for role/username
      final rows = await SupabaseClientService.client
          .from('users')
          .select('username, role')
          .eq('id', sbUser.id)
          .limit(1);

      final hasProfile = rows.isNotEmpty;
      final userRole = hasProfile
          ? (rows.first)['role']?.toString() ?? 'USER'
          : 'USER';

      if (!requiresProfileCompletion && hasProfile) {
        // User exists with profile — complete auth with backend JWT
        final displayName = (rows.first)['username']?.toString() ??
            googleUser.displayName ??
            'User';
        await login(backendToken, userRole, displayName);
        return {
          'success': true,
          'requires_profile_completion': false,
        };
      }

      // Profile completion needed
      return {
        'success': true,
        'requires_profile_completion': true,
        'email': sbUser.email ?? googleUser.email,
        'name': googleUser.displayName ?? 'Google User',
        'token': backendToken,
        'temp_token': googleAuthResponse.tempToken,
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
    String? tempToken,
  }) async {
    try {
      // If we have a backend temp_token, exchange it for a full JWT
      if (tempToken != null && tempToken.isNotEmpty) {
        final api = di.sl<ApiService>();
        final response = await api.completeGoogleProfile(
          tempToken: tempToken,
          phone: phone,
          username: username,
        );
        if (response.token.isNotEmpty) {
          await login(response.token, 'USER', username);
          return;
        }
      }

      // Fallback: upsert profile into Supabase users table directly
      // and store the provided token
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
    _pollTimer?.cancel();
    _pollTimer = null;
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
