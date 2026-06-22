import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';
import '../../firebase_options.dart';
import '../../injection_container.dart' as di;

/// Service that manages FCM push notification registration and handling.
/// On init, it requests notification permissions, obtains the device token
/// from FCM, and sends it to the backend to enable server-side push
/// notifications (e.g. when a user's role changes).
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

  /// Display a local notification when a push arrives while the app is in
  /// the foreground.
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    // Build a combined display string from title and body
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

  /// Disconnect from FCM (e.g. on logout).
  Future<void> dispose() async {
    _messaging = null;
    _deviceToken = null;
  }
}
