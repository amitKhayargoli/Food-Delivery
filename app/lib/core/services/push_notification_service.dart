import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../firebase_options.dart';
import '../../injection_container.dart' as di;
import '../../models/order.dart';
import '../services/api_service.dart';
import '../../screens/user/order_detail_screen.dart';

/// Service that manages FCM push notification registration and handling.
/// On init, it requests notification permissions, obtains the device token
/// from FCM, and sends it to the backend to enable server-side push
/// notifications (e.g. when a user's role changes).
///
/// Also handles deep linking — when the user taps a push notification,
/// the app navigates to the relevant screen (e.g. order detail for an
/// "order_update" notification, or incoming call screen for a call).
class PushNotificationService {
  static const _secureStorage = FlutterSecureStorage();
  final Dio _dio;
  FirebaseMessaging? _messaging;
  String? _deviceToken;

  PushNotificationService(this._dio);

  /// Initialize Firebase Messaging, request permissions, get the FCM token,
  /// and register it with the backend.
  Future<void> init({required String authToken}) async {
    try {
      // Ensure Firebase is initialized (idempotent) with platform options
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      _messaging = FirebaseMessaging.instance;

      // Request notification permissions (Android 13+ and iOS)
      await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Get the device's FCM token
      _deviceToken = await _messaging!.getToken();
      if (_deviceToken == null || _deviceToken!.isEmpty) {
        debugPrint('[PushNotification] No FCM token available.');
        return;
      }

      // Register the token with the backend
      await _registerToken(authToken);

      // Listen for token refresh and re-register
      _messaging!.onTokenRefresh.listen((newToken) {
        _deviceToken = newToken;
        _registerToken(authToken);
      });

      // Handle foreground messages (show in-app notification)
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle when the app is opened from a background notification tap
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Handle when the app is launched from a terminated state via notification
      _checkInitialMessage();

      // Register background message handler (static top-level function)
      FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);

      debugPrint('[PushNotification] FCM token registered successfully.');
    } catch (e) {
      debugPrint('[PushNotification] Initialization error: $e');
    }
  }

  /// Send the FCM token to the backend for storage.
  Future<void> _registerToken(String authToken) async {
    if (_deviceToken == null) return;

    try {
      await _dio.post(
        '/fcm/register-token',
        data: {'token': _deviceToken},
        options: Options(headers: {'Authorization': 'Bearer $authToken'}),
      );
    } on DioException catch (e) {
      debugPrint('[PushNotification] Token registration failed: $e');
    }
  }

  /// Handle a push notification received while the app is in the foreground.
  void _handleForegroundMessage(RemoteMessage message) {
    // Navigate to the relevant screen based on notification type
    _navigateToDeepLink(message.data);

    // Toast is handled by NotificationProvider via Realtime subscription.
    // The FCM handler only handles deep-link navigation.
  }

  /// Handle the user tapping a notification that launched/brought the app
  /// to the foreground from a background state.
  void _handleNotificationTap(RemoteMessage message) {
    _navigateToDeepLink(message.data);
  }

  /// Check if the app was launched from a terminated state by tapping a
  /// notification.
  Future<void> _checkInitialMessage() async {
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message == null) return;

      _navigateToDeepLink(message.data);
    } catch (e) {
      debugPrint('[PushNotification] getInitialMessage error: $e');
    }
  }

  /// Navigate to the screen relevant to a push notification payload.
  /// Supports: order_update, order_cancelled, delivery_assigned,
  /// rider_declined, rider_timeout, reassignment_failed, role_change.
  void _navigateToDeepLink(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final orderId = data['order_id'] as String?;

    debugPrint('[PushNotification] 🔗 Deep link: type=$type, orderId=$orderId');

    final navigatorKey = di.sl<GlobalKey<NavigatorState>>();
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('[PushNotification] ⚠ No navigator context available');
      return;
    }

    // For order-related notifications, fetch the order and navigate to it
    if (orderId != null && orderId.isNotEmpty) {
      _navigateToOrder(context, orderId, type: type);
      return;
    }

    // Role change notifications — no navigation needed
    if (type == 'role_change') {
      debugPrint('[PushNotification] 🔔 Role change notification — no navigation needed');
      return;
    }

    debugPrint('[PushNotification] ⚠ Unknown notification type: $type');
  }

  /// Fetch an order by ID and navigate to [OrderDetailScreen].
  /// If the data can't be fetched, shows a snackbar instead.
  Future<void> _navigateToOrder(
    BuildContext context,
    String orderId, {
    String? type,
  }) async {
    try {
      // Read the auth token from secure storage
      final token = await _secureStorage.read(key: 'jwt_token');
      if (token == null || token.isEmpty) {
        debugPrint('[PushNotification] ⚠ No auth token available for deep link');
        return;
      }

      final api = di.sl<ApiService>();
      final orderData = await api.getOrderById(orderId: orderId, token: token);

      if (orderData == null) {
        debugPrint('[PushNotification] ⚠ Order not found: $orderId');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('Could not load order details')),
                ],
              ),
              backgroundColor: Color(0xFFF5222D),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final order = Order.fromJson(orderData);

      if (!context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderDetailScreen(
            order: order,
            isOwner: type == 'rider_declined' ||
                type == 'rider_timeout' ||
                type == 'reassignment_failed',
          ),
        ),
      );
    } catch (e) {
      debugPrint('[PushNotification] ❌ Deep link navigation error: $e');
    }
  }

  /// Disconnect from FCM (e.g. on logout).
  Future<void> dispose() async {
    _messaging = null;
    _deviceToken = null;
  }
}

/// Static top-level background message handler.
/// Must be a top-level function (not a method) per Firebase requirements.
@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  debugPrint('[PushNotification][BG] Background notification received');
}
