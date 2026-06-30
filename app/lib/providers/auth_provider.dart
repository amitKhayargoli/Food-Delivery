import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../core/services/api_service.dart';
import '../core/services/delivery_location_service.dart';
import '../core/services/supabase_client_service.dart';
import '../core/services/push_notification_service.dart';
import '../core/services/call_service.dart';
import '../core/config/supabase_config.dart';
import '../injection_container.dart' as di;

class AuthProvider with ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  
  String? _token;
  String? _role;
  String? _username;
  String? _avatarUrl;
  List<String> _roles = ['USER'];       // All roles the user has
  String _activeRole = 'USER';          // The role the user is currently using
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
  String? get avatarUrl => _avatarUrl;

  /// All roles the user holds (e.g. ['USER', 'RESTAURANT_OWNER']).
  List<String> get roles => List.unmodifiable(_roles);

  /// The role the user is currently using to view the app.
  /// Switching this changes the navigation and available screens.
  String get activeRole => _activeRole;

  /// Roles the user can switch to (e.g. for the role switcher UI).
  /// Excludes 'ADMIN' (admin is a separate auth flow).
  List<String> get availableRoles =>
      _roles.where((r) => r != 'ADMIN').toList();

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null && !JwtDecoder.isExpired(_token!);

  /// Update the user's avatar URL (after upload) and persist it.
  Future<void> setAvatarUrl(String url) async {
    _avatarUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('avatar_url', url);
    notifyListeners();
  }

  /// Non-null when the role was just changed by a realtime update.
  /// Widgets can read this once and call [clearRoleChangeMessage] to
  /// acknowledge it (e.g. after showing a snackbar).
  String? get roleChangeMessage => _roleChangeMessage;

  void clearRoleChangeMessage() {
    _roleChangeMessage = null;
  }

  /// Switch the user's active viewing role.
  /// This changes which navigation screens are shown without a logout.
  /// The new role is persisted in SharedPreferences.
  Future<void> switchActiveRole(String newRole) async {
    if (!_roles.contains(newRole) || _activeRole == newRole) return;

    _activeRole = newRole;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_role', newRole);
    notifyListeners();
    debugPrint('[Auth] 🔄 Switched active role to: $newRole');
  }

  // ── Role Parsing ──────────────────────────────

  /// Extract roles from the JWT payload, or fall back to [role] as a single-element list.
  List<String> _parseRolesFromToken() {
    if (_token == null) return ['USER'];
    try {
      final decoded = JwtDecoder.decode(_token!);
      final raw = decoded['roles'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    if (_role != null) return [_role!];
    return ['USER'];
  }

  /// Parse the active role from SharedPreferences, falling back to the
  /// primary role or the first available role.
  Future<String> _resolveActiveRole(List<String> roles) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('active_role');
    if (saved != null && roles.contains(saved)) return saved;
    // Default to the highest-privilege role that's not USER
    for (final r in ['ADMIN', 'RESTAURANT_OWNER', 'DELIVERY_BOY', 'USER']) {
      if (roles.contains(r)) return r;
    }
    return roles.first;
  }

  // ── Realtime Subscription ─────────────────────

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
    debugPrint('[RT]   └─ current roles: $_roles, active: $_activeRole, username: $_username');

    _realtimeChannel = SupabaseClientService.client.channel(channelName);

    _realtimeChannel!.onPostgresChanges(
      event: sb.PostgresChangeEvent.update,
      schema: 'public',
      table: 'users',
      callback: (payload) {
        _subscriptionRetries = 0;

        final newRecord = payload.newRecord;
        final recordId = newRecord['id']?.toString();

        if (recordId != userId) return;

        final latestRole = newRecord['role']?.toString() ?? 'USER';
        final latestUsername = newRecord['username']?.toString() ?? 'User';
        final latestRolesRaw = newRecord['roles'];
        final List<String> latestRoles;
        if (latestRolesRaw is List) {
          latestRoles = latestRolesRaw.map((e) => e.toString()).toList();
        } else {
          latestRoles = [latestRole];
        }

        debugPrint('[RT] 📦 Realtime UPDATE — roles: $latestRoles, username: $latestUsername');
        debugPrint('[RT]   └─ stored roles: $_roles, username: $_username');

        // Only notify if something actually changed
        if (_roles.toString() == latestRoles.toString() && _username == latestUsername) {
          debugPrint('[RT]   └─ no change detected, skipping');
          return;
        }

        _onRolesChanged(latestRoles, latestRole, latestUsername);
      },
    );

    _realtimeChannel!.subscribe((status, [error]) async {
      debugPrint('[RT] 📡 Channel status: $status');
      if (error != null) {
        debugPrint('[RT] ❌ Subscribe error: $error');
      }
      if (status == sb.RealtimeSubscribeStatus.channelError ||
          status == sb.RealtimeSubscribeStatus.timedOut) {
        debugPrint('[RT] ⏹ Channel error — scheduling reconnect');
        _scheduleReconnect();
      }
    });

    debugPrint('[RT]   └─ channel subscribed, listening for UPDATE events...');
  }

  /// Handle a detected roles/role change from either Realtime or polling.
  void _onRolesChanged(List<String> latestRoles, String latestRole, String latestUsername) {
    final oldRole = _activeRole;
    _roles = latestRoles;
    _role = latestRole;
    _username = latestUsername;

    debugPrint('[RT] 🚀 Roles changed! $_roles (active: $oldRole)');

    // If the previously active role was removed, switch to a valid one
    if (!_roles.contains(_activeRole)) {
      _activeRole = _roles.contains('USER') ? 'USER' : _roles.first;
    }

    if (oldRole != _activeRole) {
      _roleChangeMessage =
          'Your role has been updated to ${_formatRole(_activeRole)}.';
    }

    // Persist asynchronously
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('user_role', latestRole);
      prefs.setString('username', latestUsername);
      prefs.setStringList('user_roles', latestRoles);
      prefs.setString('active_role', _activeRole);
    });

    notifyListeners();
  }

  void _scheduleReconnect() {
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
            .select('role, username, roles')
            .eq('id', userId)
            .limit(1);

        if (rows.isEmpty) {
          _scheduleNextIfStillActive(userId, timer);
          return;
        }

        final latestRole = (rows.first)['role']?.toString() ?? 'USER';
        final latestUsername = (rows.first)['username']?.toString() ?? 'User';
        final latestRolesRaw = rows.first['roles'];
        final List<String> latestRoles;
        if (latestRolesRaw is List) {
          latestRoles = latestRolesRaw.map((e) => e.toString()).toList();
        } else {
          latestRoles = [latestRole];
        }

        if (_roles.toString() != latestRoles.toString() || _username != latestUsername) {
          debugPrint('[RT] 📟 Poll detected roles change! $_roles → $latestRoles');

          final oldActiveRole = _activeRole;
          _roles = latestRoles;
          _role = latestRole;
          _username = latestUsername;

          if (!_roles.contains(_activeRole)) {
            _activeRole = _roles.contains('USER') ? 'USER' : _roles.first;
          }

          if (oldActiveRole != _activeRole) {
            _roleChangeMessage =
                'Your role has been updated to ${_formatRole(_activeRole)}.';
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_role', latestRole);
          await prefs.setString('username', latestUsername);
          await prefs.setStringList('user_roles', latestRoles);
          await prefs.setString('active_role', _activeRole);

          notifyListeners();
        }
      } catch (e) {
        debugPrint('[RT] 📟 Poll error: $e');
      }

      _scheduleNextIfStillActive(userId, timer);
    });
    _pollTimer = timer;
  }

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

  // ── Auth Lifecycle ────────────────────────────

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
        // Parse roles from JWT first (instant, no network)
        _roles = _parseRolesFromToken();

        // Fetch the latest user profile from Supabase
        final currentUser = SupabaseClientService.client.auth.currentUser;
        if (currentUser != null) {
          final rows = await SupabaseClientService.client
              .from('users')
              .select('username, role, roles')
              .eq('id', currentUser.id)
              .limit(1);

          if (rows.isNotEmpty) {
            final latestRole = (rows.first)['role']?.toString() ?? 'USER';
            final latestUsername =
                (rows.first)['username']?.toString() ?? 'User';
            final latestRolesRaw = rows.first['roles'];
            if (latestRolesRaw is List) {
              _roles = latestRolesRaw.map((e) => e.toString()).toList();
            } else {
              _roles = [latestRole];
            }

            _role = latestRole;
            _username = latestUsername;
            _avatarUrl = rows.first['avatar_url']?.toString();

            // Resolve active role
            _activeRole = await _resolveActiveRole(_roles);

            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_role', latestRole);
            await prefs.setString('username', latestUsername);
            await prefs.setStringList('user_roles', _roles);
            await prefs.setString('active_role', _activeRole);
            if (_avatarUrl != null) {
              await prefs.setString('avatar_url', _avatarUrl!);
            }
          }

          debugPrint('[RT] 🔌 Initializing realtime for user: ${currentUser.id}');
          _startRoleSubscription(currentUser.id);
          _startPolling(currentUser.id);

          di.sl<CallService>().init(userId: currentUser.id);
          if (_token != null) {
            di.sl<PushNotificationService>().init(authToken: _token!);
          }
        }
      }

      // Fallback to cached values
      if (_role == null) {
        final prefs = await SharedPreferences.getInstance();
        _role = prefs.getString('user_role');
        _username = prefs.getString('username');
        _avatarUrl = prefs.getString('avatar_url');
        final savedRoles = prefs.getStringList('user_roles');
        if (savedRoles != null && savedRoles.isNotEmpty) {
          _roles = savedRoles;
        }
        _activeRole = prefs.getString('active_role') ?? _role ?? 'USER';
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      _role = prefs.getString('user_role');
      _username = prefs.getString('username');
      _avatarUrl = prefs.getString('avatar_url');
      final savedRoles = prefs.getStringList('user_roles');
      if (savedRoles != null && savedRoles.isNotEmpty) {
        _roles = savedRoles;
      }
      _activeRole = prefs.getString('active_role') ?? _role ?? 'USER';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> login(String token, String role, String username, {List<String>? roles, String? avatarUrl}) async {
    String? userId;
    try {
      final decoded = JwtDecoder.decode(token);
      userId = (decoded['sub'] ?? decoded['id']) as String?;
    } catch (_) {}

    userId ??= SupabaseClientService.client.auth.currentUser?.id;

    _token = token;
    _role = role;
    _username = username;
    _roles = roles ?? [role];
    _activeRole = role;
    _avatarUrl = avatarUrl;

    await _secureStorage.write(key: 'jwt_token', value: token);

    di.sl<DeliveryLocationService>().setAuthToken(token);
    di.sl<DeliveryLocationService>().pullFromBackend();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    await prefs.setString('username', username);
    await prefs.setStringList('user_roles', _roles);
    await prefs.setString('active_role', _activeRole);
    if (_avatarUrl != null) {
      await prefs.setString('avatar_url', _avatarUrl!);
    }
    if (_avatarUrl != null) {
      await prefs.setString('avatar_url', _avatarUrl!);
    }

    if (userId != null) {
      debugPrint('[RT] 🔌 Starting realtime subscription after login for user: $userId');
      _startRoleSubscription(userId);
      _startPolling(userId);
    }

    if (userId != null) {
      di.sl<CallService>().init(userId: userId);
    }

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

      final authResponse = await SupabaseClientService.client.auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
      );

      final sbUser = authResponse.user;
      if (sbUser == null) {
        return {'success': false, 'error': 'Google authentication failed'};
      }

      final api = di.sl<ApiService>();
      GoogleAuthResponse googleAuthResponse;
      try {
        googleAuthResponse = await api.googleAuth(idToken: idToken);
      } on ApiException catch (e) {
        return {'success': false, 'error': e.message};
      }

      final String backendToken;
      final bool requiresProfileCompletion;

      final tempToken = googleAuthResponse.tempToken;
      if (tempToken != null && tempToken.isNotEmpty) {
        backendToken = tempToken;
        requiresProfileCompletion = true;
      } else if (googleAuthResponse.token.isNotEmpty) {
        backendToken = googleAuthResponse.token;
        requiresProfileCompletion = false;
      } else {
        return {'success': false, 'error': 'Failed to authenticate with server'};
      }

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
        final displayName = (rows.first)['username']?.toString() ??
            googleUser.displayName ??
            'User';
        await login(backendToken, userRole, displayName);
        return {
          'success': true,
          'requires_profile_completion': false,
        };
      }

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

    final userId = SupabaseClientService.client.auth.currentUser?.id;
    if (userId != null) {
      await SupabaseClientService.client.from('users').upsert({
        'id': userId,
        'username': username,
        'phone': phone,
        'role': 'USER',
        'roles': ['USER'],
        'status': 'ACTIVE',
      });
    }
    await login(token, 'USER', username, roles: ['USER']);
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

    di.sl<CallService>().dispose();
    di.sl<PushNotificationService>().dispose();

    _token = null;
    _role = null;
    _username = null;
    _roles = ['USER'];
    _activeRole = 'USER';

    await _secureStorage.delete(key: 'jwt_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_role');
    await prefs.remove('username');
    await prefs.remove('user_roles');
    await prefs.remove('active_role');
    await prefs.remove('avatar_url');

    notifyListeners();
  }
}
