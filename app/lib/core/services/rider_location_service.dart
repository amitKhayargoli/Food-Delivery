import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'api_service.dart';

/// Manages periodic GPS tracking for delivery riders.
///
/// Pings the backend every [normalPingInterval] seconds with the rider's
/// current position. When the device battery drops below [lowBatteryThreshold]%,
/// the ping interval is increased to [lowBatteryPingInterval] seconds to
/// conserve power. Exposes [batteryLevel] and [isLowBattery] so the UI
/// can display a battery warning indicator.
///
/// Automatically degrades when GPS signal is weak (reports last-known
/// position + accuracy) and pauses when the app is backgrounded (handled
/// by the caller via [stopTracking]/[startTracking]).
class RiderLocationService {
  final ApiService _api;
  final Battery _battery = Battery();

  RiderLocationService(this._api);

  Timer? _timer;
  StreamSubscription? _batterySubscription;
  Position? _lastKnownPosition;
  bool _isTracking = false;
  bool _isOnline = false;

  /// Current authentication token — must be set before starting tracking.
  String? _authToken;

  /// Battery level percentage (0–100), cached on each GPS ping.
  int _batteryLevel = 100;

  /// Low battery threshold in percent — below this the ping interval doubles.
  static const int lowBatteryThreshold = 20;

  // ── Ping intervals ──

  /// Normal ping interval (seconds).
  static const int normalPingInterval = 8;

  /// Extended ping interval used when battery is low (seconds).
  static const int lowBatteryPingInterval = 15;

  /// How often to check GPS (seconds).
  static const int _gpsInterval = 6;

  // ── Getters ──

  bool get isTracking => _isTracking;
  bool get isOnline => _isOnline;
  Position? get lastKnownPosition => _lastKnownPosition;

  /// Current battery level as a percentage (0–100).
  /// Defaults to 100 if unable to read battery level yet.
  int get batteryLevel => _batteryLevel;

  /// Whether the device battery is at or below the low-battery threshold.
  bool get isLowBattery => _batteryLevel <= lowBatteryThreshold;

  /// The currently active ping interval, which is automatically extended
  /// when the battery is low.
  int get activePingInterval =>
      isLowBattery ? lowBatteryPingInterval : normalPingInterval;

  // ── Token management ──

  /// Set the auth token so the service can authenticate API calls.
  void setAuthToken(String? token) {
    _authToken = token;
  }

  // ── Tracking lifecycle ──

  /// Start periodic GPS tracking.
  /// Requires location permissions — caller should request them first.
  Future<void> startTracking() async {
    if (_isTracking) return;
    if (_authToken == null) {
      debugPrint('[RiderLocation] Cannot start tracking: no auth token');
      return;
    }

    // Read initial battery level
    try {
      _batteryLevel = await _battery.batteryLevel;
    } catch (_) {
      // Battery level unavailable (e.g. desktop/emulator) — keep default
    }

    _isTracking = true;
    _isOnline = true;

    // Listen for battery state changes (charging/discharging transitions)
    _batterySubscription = _battery.onBatteryStateChanged.listen((_) {
      _updateBatteryLevel();
    });

    // Immediately ping with current location
    await _ping();

    // Then repeat on an interval (adjusted dynamically for battery)
    _scheduleNextPing();

    debugPrint(
      '[RiderLocation] Tracking started (interval: ${activePingInterval}s, '
      'battery: $_batteryLevel%)',
    );
  }

  /// Schedule the next GPS ping based on the current battery level.
  void _scheduleNextPing() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: activePingInterval),
      (_) async {
        await _ping();
      },
    );
  }

  /// Stop GPS tracking and mark rider as offline.
  Future<void> stopTracking() async {
    _isTracking = false;
    _isOnline = false;
    _timer?.cancel();
    _timer = null;
    _batterySubscription?.cancel();
    _batterySubscription = null;

    // Notify backend we're offline
    if (_authToken != null) {
      try {
        await _api.updateRiderOffline(token: _authToken!);
      } catch (_) {
        // Silently ignore — rider may not have network
      }
    }

    debugPrint('[RiderLocation] Tracking stopped, marked offline');
  }

  /// Go offline without fully stopping tracking (e.g. temporary pause).
  Future<void> goOffline() async {
    _isOnline = false;
    if (_authToken != null) {
      try {
        await _api.updateRiderOffline(token: _authToken!);
      } catch (_) {}
    }
  }

  /// Go back online (resume pings).
  Future<void> goOnline() async {
    _isOnline = true;
    // Next timer tick will ping and set is_online = true
  }

  // ── GPS ping ──

  Future<void> _ping() async {
    if (_authToken == null) return;

    try {
      final position = await _getCurrentPosition();
      if (position == null) return;

      _lastKnownPosition = position;

      // Refresh battery level before each ping
      await _updateBatteryLevel();

      await _api.updateRiderLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        heading: position.heading,
        speed: position.speed,
        accuracy: position.accuracy,
        token: _authToken!,
      );
    } catch (e) {
      debugPrint('[RiderLocation] Ping failed: $e');
      // If we have a last-known position, we could send that instead
      // with reduced accuracy — for now, skip this ping cycle
    }
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: _gpsInterval),
      );
      return position;
    } on TimeoutException {
      debugPrint('[RiderLocation] GPS timeout — using last known');
      return _lastKnownPosition;
    } catch (e) {
      debugPrint('[RiderLocation] GPS error: $e');
      return _lastKnownPosition;
    }
  }

  // ── Battery helpers ──

  /// Refresh the cached battery level from the platform.
  /// If battery drops to/below the low threshold, reschedule the timer
  /// with the extended interval (and vice versa if it recovers).
  Future<void> _updateBatteryLevel() async {
    try {
      final previousLevel = _batteryLevel;
      _batteryLevel = await _battery.batteryLevel;

      // If battery crossed the threshold, re-schedule with new interval
      final wasLow = previousLevel <= lowBatteryThreshold;
      final nowLow = _batteryLevel <= lowBatteryThreshold;
      if (wasLow != nowLow && _timer != null) {
        _scheduleNextPing();
        debugPrint(
          '[RiderLocation] Battery ${nowLow ? "dropped to" : "recovered to"} '
          '$_batteryLevel% — interval changed to ${activePingInterval}s',
        );
      }
    } catch (_) {
      // Battery info unavailable — continue with current settings
    }
  }

  // ── Permission helpers ──

  /// Request location permissions. Returns true if granted.
  Future<bool> requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[RiderLocation] Location services disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('[RiderLocation] Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[RiderLocation] Location permission permanently denied');
      return false;
    }

    return true;
  }

  /// Dispose — clean up resources.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _batterySubscription?.cancel();
    _batterySubscription = null;
    _isTracking = false;
  }
}
