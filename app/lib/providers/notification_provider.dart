import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../core/services/api_service.dart';
import '../core/services/supabase_client_service.dart';
import '../widgets/notification_toast.dart';
/// A single notification entry.
class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final Map<String, dynamic> data;
  bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.data = const {},
    this.isRead = false,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      type: json['type'] as String? ?? 'general',
      data: json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : {},
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': data,
        'is_read': isRead,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Provider that manages in-app notifications:
/// - Fetches notification history from the backend
/// - Subscribes to Realtime for live notifications
/// - Shows overlay toast when a new notification arrives
/// - Tracks unread count for the bell badge
class NotificationProvider with ChangeNotifier {
  final ApiService _apiService;
  List<AppNotification> _notifications = [];
  bool _isLoading = false;
  int _unreadCount = 0;
  sb.RealtimeChannel? _realtimeChannel;

  /// The currently active role used to filter notifications
  /// (e.g. 'customer', 'owner', 'rider', 'admin').
  String _currentRole = 'customer';

  /// The auth token used for API calls.
  String? _currentToken;

  /// IDs we've already processed via Realtime (persistent across refreshes).
  /// This catches duplicate Realtime events delivering the same row.
  final Set<String> _processedRealtimeIds = {};

  /// Content-based dedup: tracks (title+body) timestamps to catch
  /// backend-duplicated rows with different IDs within a short window.
  final Map<int, DateTime> _recentContentHashes = {};
  static const _contentDedupWindow = Duration(seconds: 5);

  NotificationProvider(this._apiService);

  // ── Getters ──

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  bool get isLoading => _isLoading;
  int get unreadCount => _unreadCount;
  bool get hasUnread => _unreadCount > 0;
  String get currentRole => _currentRole;

  // ── Lifecycle ──

  /// Initialize: fetch notifications and start Realtime subscription.
  Future<void> init(String token, String userId, {String role = 'customer'}) async {
    _currentToken = token;
    _currentRole = role;
    _stopRealtime();
    await fetchNotifications(token, role: role);
    _startRealtime(userId);
  }

  /// Update the active role without re-fetching. Call [refresh] to re-fetch.
  void setRole(String role) {
    _currentRole = role;
    notifyListeners();
  }

  /// Fetch notifications from the backend, optionally filtered by role.
  Future<void> fetchNotifications(String token, {String? role}) async {
    _currentToken = token;
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _apiService.getNotifications(
        token: token,
        role: role ?? _currentRole,
      );
      final rawList = (result['notifications'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      _notifications =
          rawList.map((json) => AppNotification.fromJson(json)).toList();
      _unreadCount = (result['unread_count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[Notifications] Fetch error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Re-fetch notifications with the currently active role.
  Future<void> refresh() async {
    if (_currentToken == null) return;
    await fetchNotifications(_currentToken!, role: _currentRole);
  }

  /// Mark a single notification as read (optimistic + API).
  Future<void> markAsRead(String notificationId, String token) async {
    // Optimistic update
    final idx = _notifications.indexWhere((n) => n.id == notificationId);
    if (idx == -1) return;
    if (_notifications[idx].isRead) return;

    _notifications[idx].isRead = true;
    _unreadCount = (_unreadCount - 1).clamp(0, _notifications.length);
    notifyListeners();

    try {
      await _apiService.markNotificationAsRead(
        notificationId: notificationId,
        token: token,
      );
    } catch (e) {
      debugPrint('[Notifications] Mark read error: $e');
      // Revert on failure
      _notifications[idx].isRead = false;
      _unreadCount++;
      notifyListeners();
    }
  }

  /// Mark all notifications as read (optimistic + API).
  Future<void> markAllAsRead(String token) async {
    final changed = <int>[];
    for (int i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        _notifications[i].isRead = true;
        changed.add(i);
      }
    }
    _unreadCount = 0;
    notifyListeners();

    try {
      await _apiService.markAllNotificationsAsRead(token: token);
    } catch (e) {
      debugPrint('[Notifications] Mark all read error: $e');
      // Revert
      for (final i in changed) {
        _notifications[i].isRead = false;
      }
      _unreadCount = changed.length;
      notifyListeners();
    }
  }

  // ── Realtime Subscription ──

  void _startRealtime(String userId) {
    _stopRealtime();

    final channelName = 'notifications-$userId';
    _realtimeChannel = SupabaseClientService.client.channel(channelName);

    _realtimeChannel!.onPostgresChanges(
      event: sb.PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      callback: (payload) {
        final newRecord = payload.newRecord;
        final recordUserId = newRecord['user_id']?.toString();
        if (recordUserId != userId) return;

        // ── Role-based filtering: skip notifications not intended for
        //    the currently active role (e.g. owner notif while in customer mode).
        final recordRole = newRecord['role']?.toString();
        if (recordRole != null && recordRole != _currentRole) {
          debugPrint('[Notifications] ⏭ Role mismatch: got "$recordRole", active "$_currentRole"');
          return;
        }

        final notification = AppNotification.fromJson(
          Map<String, dynamic>.from(newRecord as Map),
        );

        // ── Layer 1: ID-based deduplication ──
        // Catches the exact same row being delivered twice by Realtime.
        if (_processedRealtimeIds.contains(notification.id)) {
          debugPrint('[Notifications] ⏭ ID dedup: ${notification.id}');
          return;
        }

        // ── Layer 2: Content-based deduplication ──
        // Catches the same notification inserted with different IDs
        // (e.g. backend retry logic that duplicates rows).
        final contentHash = Object.hash(
          notification.title,
          notification.body,
          notification.type,
        );
        final lastSeen = _recentContentHashes[contentHash];
        if (lastSeen != null &&
            DateTime.now().difference(lastSeen) < _contentDedupWindow) {
          debugPrint('[Notifications] ⏭ Content dedup: ${notification.title}');
          return;
        }
        _recentContentHashes[contentHash] = DateTime.now();

        // Trim stale content hashes to keep the map lean
        if (_recentContentHashes.length > 50) {
          final cutoff = DateTime.now().subtract(_contentDedupWindow);
          _recentContentHashes.removeWhere((_, t) => t.isBefore(cutoff));
        }

        // ── Record the ID and add to list ──
        _processedRealtimeIds.add(notification.id);

        _notifications.insert(0, notification);
        _unreadCount++;
        notifyListeners();

        // Show overlay toast
        _showToast(notification);
      },
    );

    _realtimeChannel!.subscribe((status, [error]) {
      debugPrint('[RT-Notifications] Channel status: $status');
      if (error != null) debugPrint('[RT-Notifications] Error: $error');
    });
  }

  void _stopRealtime() {
    if (_realtimeChannel != null) {
      SupabaseClientService.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  // ── Toast Overlay ──

  /// Show a notification toast that slides in from the top of the screen.
  void _showToast(AppNotification notification) {
    showNotificationToast(
      title: notification.title,
      body: notification.body,
      type: notification.type,
    );
  }

  @override
  void dispose() {
    _stopRealtime();
    super.dispose();
  }
}

