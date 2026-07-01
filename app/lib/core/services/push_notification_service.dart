import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import '../../firebase_options.dart';
import '../../injection_container.dart' as di;
import '../../providers/call_provider.dart';
import '../../models/call.dart';

/// Service that manages FCM push notification registration and handling.
/// On init, it requests notification permissions, obtains the device token
/// from FCM, and sends it to the backend to enable server-side push
/// notifications (e.g. when a user's role changes).
///
/// Also handles incoming call data payloads — when the app receives an
/// "incoming_call" push, it automatically shows the IncomingCallScreen.
class PushNotificationService {
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
    // Check if this is an incoming call payload
    final data = message.data;
    if (data['type'] == 'incoming_call') {
      _handleIncomingCallPayload(data);
      return;
    }

    // Otherwise show a standard snackbar notification
    final notification = message.notification;
    if (notification == null) return;

    final parts = [notification.title, notification.body]
        .where((s) => s != null && s.isNotEmpty)
        .join(': ');
    if (parts.isEmpty) return;

    final navigatorKey = di.sl<GlobalKey<NavigatorState>>();
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parts),
          backgroundColor: const Color(0xFF1A1C1C),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Handle the user tapping a notification that launched/brought the app
  /// to the foreground from a background state.
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'incoming_call') {
      _handleIncomingCallPayload(data);
    }
  }

  /// Check if the app was launched from a terminated state by tapping a
  /// notification (e.g. an incoming call push).
  Future<void> _checkInitialMessage() async {
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null && message.data['type'] == 'incoming_call') {
        _handleIncomingCallPayload(message.data);
      }
    } catch (e) {
      debugPrint('[PushNotification] getInitialMessage error: $e');
    }
  }

  /// Process an incoming call data payload from FCM.
  /// Parses the call info and triggers the incoming call UI via CallProvider.
  void _handleIncomingCallPayload(Map<String, dynamic> data) {
    try {
      final callId = data['call_id'] as String?;
      final callerId = data['caller_id'] as String?;
      final callerName = data['caller_name'] as String? ?? 'Caller';
      final channelName = data['channel_name'] as String?;

      if (callId == null || callerId == null || channelName == null) return;

      debugPrint('[PushNotification] 📞 Incoming call from $callerName ($callerId)');

      // Create a Call object and push it to CallProvider
      // The AppNavigation widget watches CallProvider and will auto-navigate
      // to IncomingCallScreen.
      final navigatorKey = di.sl<GlobalKey<NavigatorState>>();
      final context = navigatorKey.currentContext;
      if (context == null) return;

      final callProvider = context.read<CallProvider>();
      final incomingCall = Call(
        id: callId,
        callerId: callerId,
        calleeId: '', // We'll get this from the DB sync
        orderId: data['order_id'] as String?,
        status: CallStatus.calling,
        channelName: channelName,
        createdAt: DateTime.now(),
        callerName: callerName,
        callerRole: data['caller_role'] as String?,
      );

      callProvider.service.triggerIncomingCall(incomingCall);
    } catch (e) {
      debugPrint('[PushNotification] Incoming call handling error: $e');
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
  final data = message.data;
  if (data['type'] == 'incoming_call') {
    // For background handling, we rely on the system notification
    // that was already shown by the FCM server. When the user taps it,
    // onMessageOpenedApp or getInitialMessage will handle navigation.
    debugPrint('[PushNotification][BG] Incoming call notification received');
  }
}
