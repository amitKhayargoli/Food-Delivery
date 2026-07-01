import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/call_service.dart';
import '../models/call.dart';

/// Manages the in-app calling state and provides it to the UI.
/// Wraps [CallService] and exposes reactive state for screens.
class CallProvider with ChangeNotifier {
  final CallService _callService;

  Call? _incomingCall;
  Call? _activeCall;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCaller = false;
  String _callDuration = '00:00';
  Timer? _durationTimer;

  StreamSubscription<Call?>? _callSub;
  StreamSubscription<bool>? _muteSub;
  StreamSubscription<bool>? _speakerSub;

  CallProvider(this._callService) {
    _setupListeners();
  }

  // ── Getters ──

  CallService get service => _callService;
  Call? get incomingCall => _incomingCall;
  Call? get activeCall => _activeCall;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isCaller => _isCaller;
  bool get isInCall => _activeCall != null;
  String get callDuration => _callDuration;

  // ── Setup ──

  void _setupListeners() {
    // Listen for call state changes
    _callSub = _callService.callStream.listen((call) {
      if (call == null || !call.isActive) {
        _activeCall = null;
        _incomingCall = null;
        _stopDurationTimer();
      } else if (call.isMeCaller || call.status == CallStatus.connected) {
        _activeCall = call;
        _incomingCall = null;
        _isCaller = call.isMeCaller || _isCaller;
        _startDurationTimer();
      }

      notifyListeners();
    });

    // Listen for mute changes
    _muteSub = _callService.muteStream.listen((muted) {
      _isMuted = muted;
      notifyListeners();
    });

    // Listen for speaker changes
    _speakerSub = _callService.speakerStream.listen((speakerOn) {
      _isSpeakerOn = speakerOn;
      notifyListeners();
    });

    // Handle incoming call callback
    _callService.onIncomingCall = (call) {
      _incomingCall = call;
      _isCaller = false;
      notifyListeners();
    };

    // Handle call ended
    _callService.onCallEnded = (result) {
      _activeCall = null;
      _incomingCall = null;
      _stopDurationTimer();
      notifyListeners();
    };
  }

  // ── Actions ──

  /// Initiate a call to another user.
  Future<CallInitResult> startCall({
    required String calleeId,
    String? orderId,
  }) async {
    final result = await _callService.startCall(
      calleeId: calleeId,
      orderId: orderId,
    );
    if (result.success && result.call != null) {
      _activeCall = result.call;
      _isCaller = true;
      notifyListeners();
    }
    return result;
  }

  /// Accept the incoming call.
  Future<CallInitResult> acceptCall() async {
    final result = await _callService.acceptCall();
    if (result.success && result.call != null) {
      _activeCall = result.call;
      _incomingCall = null;
      _isCaller = false;
      notifyListeners();
    }
    return result;
  }

  /// Reject the incoming call.
  Future<void> rejectCall() async {
    await _callService.rejectCall();
    _incomingCall = null;
    notifyListeners();
  }

  /// End the current active call.
  Future<CallEndResult> endCall() async {
    final result = await _callService.endCall();
    _activeCall = null;
    _incomingCall = null;
    _stopDurationTimer();
    notifyListeners();
    return result;
  }

  /// Toggle microphone mute.
  Future<void> toggleMute() async {
    await _callService.toggleMute();
  }

  /// Toggle speakerphone.
  Future<void> toggleSpeaker() async {
    await _callService.toggleSpeaker();
  }

  /// Clear any pending incoming call (e.g. on screen dismiss).
  void clearIncomingCall() {
    _incomingCall = null;
    notifyListeners();
  }

  // ── Duration Timer ──

  void _startDurationTimer() {
    _stopDurationTimer();
    final startedAt = _activeCall?.startedAt ?? DateTime.now();
    _callDuration = '00:00';

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeCall?.startedAt != null) {
        final elapsed = DateTime.now().difference(startedAt);
        final min = elapsed.inMinutes.remainder(60);
        final sec = elapsed.inSeconds.remainder(60);
        _callDuration =
            '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
        notifyListeners();
      }
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _callDuration = '00:00';
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _muteSub?.cancel();
    _speakerSub?.cancel();
    _stopDurationTimer();
    _callService.onIncomingCall = null;
    _callService.onCallEnded = null;
    super.dispose();
  }
}
