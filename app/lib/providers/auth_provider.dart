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
import '../core/config/supabase_config.dart';
import '../injection_container.dart' as di;

class AuthProvider with ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  
  String? _token;
  String? _role;
  String? _username;
  String? _email;
  String? _phone;
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
  String? get email => _email;
  String? get phone => _phone;
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

  /// Update the in-memory token (called by AuthInterceptor after a refresh).
  /// Does NOT trigger a full re-login — just replaces the stored token
  /// so all future API calls use the fresh one.
  void setToken(String newToken) {
    _token = newToken;
    notifyListeners();
  }

  /// Update the user's avatar URL (after upload) and persist it.
  Future<void> setAvatarUrl(String url) async {
    _avatarUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('avatar_url', url);
    notifyListeners();
  }

  /// Update the user's display name in memory + SharedPreferences.
  Future<void> updateUsername(String newUsername) async {
    _username = newUsername;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', newUsername);
    notifyListeners();
  }

  /// Update the user's phone in memory + SharedPreferences.
  Future<void> updatePhone(String newPhone) async {
    _phone = newPhone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone', newPhone);
    notifyListeners();
  }

  /// Update the user's email in memory + SharedPreferences.
  Future<void> updateEmail(String newEmail) async {
    _email = newEmail;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('email', newEmail);
    notifyListeners();
  }

  /// Strip out placeholder emails (e.g. "{phone}@placeholder.local" created
  /// by the backend for phone-only signups) so they never appear in the UI.
  String? _cleanEmail(String? email) {
    if (email == null || email.endsWith('@placeholder.local')) return null;
    return email;
  }

  /// Normalize a single role name — maps 'CUSTOMER' to 'USER' since they
  /// are functionally equivalent in the app (both refer to the customer role).
  /// This allows the database to store either value without breaking the UI.
  String _normalizeRole(String role) {
    return role == 'CUSTOMER' ? 'USER' : role;
  }

  /// Normalize a list of roles — applies [_normalizeRole] to each entry.
  List<String> _normalizeRoles(List<String> roles) {
    return roles.map(_normalizeRole).toList();
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
  /// Normalizes 'CUSTOMER' to 'USER' for consistency.
  List<String> _parseRolesFromToken() {
    if (_token == null) return ['USER'];
    try {
      final decoded = JwtDecoder.decode(_token!);
      final raw = decoded['roles'];
      if (raw is List) {
        return _normalizeRoles(raw.map((e) => e.toString()).toList());
      }
    } catch (_) {}
    if (_role != null) return [_normalizeRole(_role!)];
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

        final latestRole = newRecord['role']?.toString();
        final latestUsername = newRecord['username']?.toString();
        final latestRolesRaw = newRecord['roles'];

        // --- Critical safeguard ---
        // If the `roles` column is NOT present as a List in the Realtime
        // payload (e.g. the database row has a NULL or mismatched roles
        // array), we MUST NOT overwrite the in-memory roles. Doing so
        // would lose roles like DELIVERY_BOY or RESTAURANT_OWNER and
        // cause the app to fall back to a basic customer view.
        //
        // Preserve existing `_roles` in that case, falling back to the
        // primary `role` only when even that is missing.
        final resolvedRole = _normalizeRole(latestRole ?? _role ?? 'USER');
        final resolvedUsername = latestUsername ?? _username ?? 'User';
        final List<String> latestRoles;
        if (latestRolesRaw is List) {
          latestRoles = _normalizeRoles(latestRolesRaw.map((e) => e.toString()).toList());
        } else {
          latestRoles = List<String>.from(_roles);
        }

        debugPrint('[RT] 📦 Realtime UPDATE — roles: $latestRoles, username: $resolvedUsername');
        debugPrint('[RT]   └─ stored roles: $_roles, username: $_username');

        // Only notify if something actually changed
        if (_roles.toString() == latestRoles.toString() && _username == resolvedUsername) {
          debugPrint('[RT]   └─ no change detected, skipping');
          return;
        }

        _onRolesChanged(latestRoles, resolvedRole, resolvedUsername);
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

    // ── Ensure the primary role is always in the roles array ──
    // The database `roles` column may be out of sync with the `role` column
    // (e.g. `role = 'DELIVERY_BOY'` but `roles = ['CUSTOMER']`). If the
    // primary role isn't in the array, add it so the user doesn't lose it.
    final normalizedPrimary = _normalizeRole(latestRole);
    var mergedRoles = _normalizeRoles(latestRoles);
    if (!mergedRoles.contains(normalizedPrimary)) {
      mergedRoles = [normalizedPrimary, ...mergedRoles];
      debugPrint('[RT] 🔧 Added primary role "$normalizedPrimary" to roles → $mergedRoles');
    }

    _roles = mergedRoles;
    _role = normalizedPrimary;
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
            .select('role, username, roles, avatar_url')
            .eq('id', userId)
            .limit(1);

        if (rows.isEmpty) {
          _scheduleNextIfStillActive(userId, timer);
          return;
        }

        final latestRole = _normalizeRole(
            (rows.first)['role']?.toString() ?? 'USER');
        final latestUsername = (rows.first)['username']?.toString() ?? 'User';
        final latestRolesRaw = rows.first['roles'];
        final List<String> latestRoles;
        if (latestRolesRaw is List) {
          latestRoles = _normalizeRoles(
              latestRolesRaw.map((e) => e.toString()).toList());
        } else {
          // Poll always selects 'roles' explicitly, but guard nonetheless
          latestRoles = List<String>.from(_roles);
        }

        if (_roles.toString() != latestRoles.toString() || _username != latestUsername) {
          debugPrint('[RT] 📟 Poll detected roles change! $_roles → $latestRoles');

          // ── Same normalization as _onRolesChanged ──
          final normalizedPrimary = _normalizeRole(latestRole);
          var mergedRoles = _normalizeRoles(latestRoles);
          if (!mergedRoles.contains(normalizedPrimary)) {
            mergedRoles = [normalizedPrimary, ...mergedRoles];
          }

          final oldActiveRole = _activeRole;
          _roles = mergedRoles;
          _role = normalizedPrimary;
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
              .select('username, email, phone, role, roles, avatar_url')
              .eq('id', currentUser.id)
              .limit(1);

          if (rows.isNotEmpty) {
            final latestRole = _normalizeRole(
                (rows.first)['role']?.toString() ?? 'USER');
            final latestUsername =
                (rows.first)['username']?.toString() ?? 'User';
            final latestEmail =
                (rows.first)['email']?.toString();
            final latestPhone =
                (rows.first)['phone']?.toString();
            final latestRolesRaw = rows.first['roles'];          if (latestRolesRaw is List) {
            _roles = _normalizeRoles(latestRolesRaw.map((e) => e.toString()).toList());
          } else {
            _roles = [latestRole];
          }

          // ── Same normalization as _onRolesChanged ──
          if (!_roles.contains(_role)) {
            _roles = [_role!, ..._roles];
          }

            _role = latestRole;
            _username = latestUsername;
            _email = _cleanEmail(latestEmail);
            _phone = latestPhone;
            _avatarUrl = rows.first['avatar_url']?.toString();

            // Resolve active role
            _activeRole = await _resolveActiveRole(_roles);

            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_role', latestRole);
            await prefs.setString('username', latestUsername);
            await prefs.setString('email', _email ?? '');
            await prefs.setString('phone', latestPhone ?? '');
            await prefs.setStringList('user_roles', _roles);
            await prefs.setString('active_role', _activeRole);
            if (_avatarUrl != null) {
              await prefs.setString('avatar_url', _avatarUrl!);
            }
          }

          // Ensure phone is loaded from SharedPreferences if not available from DB
          if (_phone == null || _phone!.isEmpty) {
            final prefs = await SharedPreferences.getInstance();
            final cachedPhone = prefs.getString('phone');
            if (cachedPhone != null && cachedPhone.isNotEmpty) {
              _phone = cachedPhone;
            }
          }

          debugPrint('[RT] 🔌 Initializing realtime for user: ${currentUser.id}');
          _startRoleSubscription(currentUser.id);
          _startPolling(currentUser.id);

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
        _email = _cleanEmail(prefs.getString('email'));
        _phone = prefs.getString('phone');
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
      _email = _cleanEmail(prefs.getString('email'));
      _phone = prefs.getString('phone');
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

  Future<void> login(String token, String role, String username, {List<String>? roles, String? avatarUrl, String? email, String? phone}) async {
    String? userId;
    try {
      final decoded = JwtDecoder.decode(token);
      userId = (decoded['sub'] ?? decoded['id']) as String?;
    } catch (_) {}

    userId ??= SupabaseClientService.client.auth.currentUser?.id;

    final normalizedRole = _normalizeRole(role);
    _token = token;
    _role = normalizedRole;
    _username = username;
    _email = _cleanEmail(email);
    _phone = phone;
    _roles = roles != null ? _normalizeRoles(roles) : [normalizedRole];
    _activeRole = normalizedRole;
    _avatarUrl = avatarUrl;

    await _secureStorage.write(key: 'jwt_token', value: token);

    di.sl<DeliveryLocationService>().setAuthToken(token);
    di.sl<DeliveryLocationService>().pullFromBackend();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    await prefs.setString('username', username);
    await prefs.setString('email', email ?? '');
    await prefs.setString('phone', phone ?? '');
    await prefs.setStringList('user_roles', _roles);
    await prefs.setString('active_role', _activeRole);
    if (_avatarUrl != null) {
      await prefs.setString('avatar_url', _avatarUrl!);
    }

    if (userId != null) {
      debugPrint('[RT] 🔌 Starting realtime subscription after login for user: $userId');
      _startRoleSubscription(userId);
      _startPolling(userId);
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
          .select('username, role, roles, phone, email, avatar_url')
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
        final profileRoles = (rows.first)['roles'];
        final profilePhone = (rows.first)['phone']?.toString();
        final profileEmail = (rows.first)['email']?.toString();
        final profileAvatar = (rows.first)['avatar_url']?.toString();
        final List<String> allRoles;
        if (profileRoles is List) {
          allRoles = profileRoles.map((e) => e.toString()).toList();
        } else {
          allRoles = [userRole];
        }
        await login(
          backendToken,
          userRole,
          displayName,
          roles: allRoles,
          phone: profilePhone,
          email: profileEmail,
          avatarUrl: profileAvatar,
        );
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
        await login(response.token, 'USER', username, phone: phone);
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
    await login(token, 'USER', username, roles: ['USER'], phone: phone);
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
