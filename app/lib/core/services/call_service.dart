import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:dio/dio.dart';
import '../../models/call.dart';
import '../config/supabase_config.dart';
import 'supabase_client_service.dart';

/// STUN/TURN servers for WebRTC peer-to-peer connection.
/// flutter_webrtc uses a raw Map configuration — no RTCIceServer class.
final Map<String, dynamic> _iceConfiguration = {
  'iceServers': [
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
  ],
};

/// Key used for the Supabase Realtime broadcast event that carries
/// WebRTC signaling messages (SDP offer/answer, ICE candidates).
const String _signalEventKey = 'webrtc_signal';

/// Result returned when initiating or receiving a call.
class CallInitResult {
  final bool success;
  final String? error;
  final Call? call;

  const CallInitResult({this.success = false, this.error, this.call});
}

/// Result returned when ending a call.
class CallEndResult {
  final bool success;
  final int? durationSeconds;

  const CallEndResult({this.success = false, this.durationSeconds});
}

/// ──────────────────────────────────────────────
///  CallService — Manages in-app voice calling
///  using WebRTC (flutter_webrtc) for audio and
///  Supabase Realtime for signaling.
/// ──────────────────────────────────────────────
class CallService {
  // ── WebRTC ──
  webrtc.RTCPeerConnection? _pc;
  webrtc.MediaStream? _localStream;
  bool _isMuted = false;
  bool _isSpeakerOn = false;

  // ── Supabase Realtime ──
  sb.RealtimeChannel? _signalChannel;
  sb.RealtimeChannel? _callStateChannel;

  // ── Call State ──
  Call? _currentCall;
  String? _currentUserId;
  bool _isCaller = false;

  // ── Streams for UI ──
  final StreamController<Call?> _callController =
      StreamController<Call?>.broadcast();
  final StreamController<bool> _muteController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _speakerController =
      StreamController<bool>.broadcast();

  // Callbacks set by the CallProvider/Screens
  void Function(Call call)? onIncomingCall;
  void Function(Call call)? onCallAccepted;
  void Function(CallEndResult result)? onCallEnded;

  /// Stream that emits call state changes.
  Stream<Call?> get callStream => _callController.stream;
  Stream<bool> get muteStream => _muteController.stream;
  Stream<bool> get speakerStream => _speakerController.stream;

  Call? get currentCall => _currentCall;
  bool get isInCall => _currentCall != null && _currentCall!.isActive;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;

  // ──────────────────────────────────────────────
  //  Initialize / Dispose
  // ──────────────────────────────────────────────

  /// Initialize the service with the current user's ID.
  /// Sets up a listener on the `calls` table so the user gets notified
  /// of incoming calls via Realtime.
  Future<void> init({required String userId}) async {
    _currentUserId = userId;
    _listenForIncomingCalls();
  }

  /// Clean up all resources — WebRTC peer connection, media streams,
  /// Supabase channels, and stream controllers.
  Future<void> dispose() async {
    await _hangUpWebRTC();
    _signalChannel?.unsubscribe();
    _callStateChannel?.unsubscribe();
    await _callController.close();
    await _muteController.close();
    await _speakerController.close();
    _currentCall = null;
    _currentUserId = null;
    onIncomingCall = null;
    onCallAccepted = null;
    onCallEnded = null;
  }

  // ──────────────────────────────────────────────
  //  Subscribe to incoming calls via Realtime
  // ──────────────────────────────────────────────

  void _listenForIncomingCalls() {
    final userId = _currentUserId;
    if (userId == null) return;

    _callStateChannel = SupabaseClientService.client.channel('calls-$userId');

    _callStateChannel!.onPostgresChanges(
      event: sb.PostgresChangeEvent.insert,
      schema: 'public',
      table: 'calls',
      callback: (payload) {
        final record = payload.newRecord;
        final calleeId = record['callee_id']?.toString();

        // Only handle calls addressed to us
        if (calleeId != userId) return;

        final call = Call.fromJson(Map<String, dynamic>.from(record));
        debugPrint('[CallService] 📞 Incoming call from ${call.callerId}');

        _currentCall = call;
        _isCaller = false;
        _callController.add(call);

        // Notify the UI via callback
        onIncomingCall?.call(call);
      },
    );

    _callStateChannel!.onPostgresChanges(
      event: sb.PostgresChangeEvent.update,
      schema: 'public',
      table: 'calls',
      callback: (payload) {
        final record = payload.newRecord;
        final callId = record['id']?.toString();
        if (_currentCall?.id != callId) return;

        final newStatus = CallStatus.fromString(
          record['status'] as String? ?? 'MISSED',
        );

        debugPrint('[CallService] 📞 Call ${_currentCall?.id} status → $newStatus');

        if (newStatus == CallStatus.ended ||
            newStatus == CallStatus.missed) {
          final oldCall = _currentCall;
          _currentCall = Call(
            id: oldCall?.id ?? '',
            callerId: oldCall?.callerId ?? '',
            calleeId: oldCall?.calleeId ?? '',
            orderId: oldCall?.orderId,
            status: newStatus,
            channelName: oldCall?.channelName ?? '',
            startedAt: oldCall?.startedAt,
            endedAt: _parseDateTime(record['ended_at'] as String?),
            durationSeconds: (record['duration_seconds'] as num?)?.toInt(),
            createdAt: oldCall?.createdAt ?? DateTime.now(),
            callerName: oldCall?.callerName,
            calleeName: oldCall?.calleeName,
            callerRole: oldCall?.callerRole,
            calleeRole: oldCall?.calleeRole,
          );
          _callController.add(_currentCall);
          onCallEnded?.call(CallEndResult(
            success: true,
            durationSeconds: _currentCall?.durationSeconds,
          ));
        } else if (newStatus == CallStatus.connected &&
            _isCaller) {
          // Caller hears that callee accepted
          final oldCall = _currentCall;
      _currentCall = Call(
        id: oldCall!.id,
        callerId: oldCall.callerId,
        calleeId: oldCall.calleeId,
        orderId: oldCall.orderId,
        status: CallStatus.connected,
        channelName: oldCall.channelName,
        startedAt: _parseDateTime(record['started_at'] as String?),
            endedAt: null,
            durationSeconds: null,
            createdAt: oldCall.createdAt,
          );
          _callController.add(_currentCall);
          onCallAccepted?.call(_currentCall!);
        }
      },
    );

    _callStateChannel!.subscribe((status, [error]) {
      debugPrint('[CallService] Call state channel: $status');
      if (error != null) debugPrint('[CallService] Channel error: $error');
    });
  }

  // ──────────────────────────────────────────────
  //  Signaling via Supabase Realtime Broadcast
  // ──────────────────────────────────────────────

  /// Subscribe to the signaling channel for a specific call.
  /// Broadcasts are used to exchange WebRTC SDP offers/answers and
  /// ICE candidates between the two peers.
  void _subscribeToSignaling(String channelName) {
    _signalChannel?.unsubscribe();
    _signalChannel = SupabaseClientService.client.channel(channelName);

    _signalChannel!.onBroadcast(
      event: _signalEventKey,
      callback: (Map<String, dynamic> payload) {
        final type = payload['type'] as String?;
        final senderId = payload['sender_id'] as String?;

        // Ignore our own messages
        if (senderId == _currentUserId) return;
        _handleSignalMessage(type, payload);
      },
    );

    _signalChannel!.subscribe((status, [error]) {
      debugPrint('[CallService] Signal channel $channelName: $status');
      if (error != null) debugPrint('[CallService] Signal error: $error');
    });
  }

  /// Send a signaling message over the Realtime broadcast channel.
  Future<void> _sendSignal(Map<String, dynamic> data) async {
    if (_signalChannel == null) return;
    try {
      await _signalChannel!.sendBroadcastMessage(
        event: _signalEventKey,
        payload: {
          ...data,
          'sender_id': _currentUserId,
        },
      );
    } catch (e) {
      debugPrint('[CallService] Signal send error: $e');
    }
  }

  /// Handle an incoming signaling message (SDP or ICE candidate).
  Future<void> _handleSignalMessage(
    String? type,
    Map<String, dynamic> data,
  ) async {
    if (_pc == null) return;

    try {
      switch (type) {
        case 'offer':
          final sdp = data['sdp'] as String?;
          if (sdp == null) return;
          await _pc!.setRemoteDescription(
            webrtc.RTCSessionDescription(sdp, 'offer'),
          );
          // Create and send answer
          final answer = await _pc!.createAnswer();
          await _pc!.setLocalDescription(answer);
          await _sendSignal({
            'type': 'answer',
            'sdp': answer.sdp,
          });
          break;

        case 'answer':
          final sdp = data['sdp'] as String?;
          if (sdp == null) return;
          await _pc!.setRemoteDescription(
            webrtc.RTCSessionDescription(sdp, 'answer'),
          );
          break;

        case 'ice-candidate':
          final candidate = data['candidate'] as String?;
          final sdpMid = data['sdpMid'] as String?;
          final sdpMLineIndex = data['sdpMLineIndex'] as int?;
          if (candidate == null || sdpMid == null || sdpMLineIndex == null) {
            return;
          }
          await _pc!.addCandidate(
            webrtc.RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
          );
          break;

        default:
          debugPrint('[CallService] Unknown signal type: $type');
      }
    } catch (e) {
      debugPrint('[CallService] Signal handling error: $e');
    }
  }

  // ──────────────────────────────────────────────
  //  WebRTC Peer Connection
  // ──────────────────────────────────────────────

  /// Create and configure the RTCPeerConnection.
  Future<webrtc.RTCPeerConnection?> _createPeerConnection() async {
    try {
      final pc = await webrtc.createPeerConnection(_iceConfiguration);

      // Get local audio stream
      final stream = await webrtc.navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      _localStream = stream;

      // Add audio track to peer connection
      stream.getAudioTracks().forEach((track) {
        pc.addTrack(track, stream);
      });

      // ICE candidate handler — send candidates to the peer
      pc.onIceCandidate = (candidate) {
        _sendSignal({
          'type': 'ice-candidate',
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };

      // Connection state changes
      pc.onConnectionState = (state) {
        debugPrint('[CallService] Connection state: $state');
        if (state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _endCallLocally();
        }
      };

      _pc = pc;
      return pc;
    } catch (e) {
      debugPrint('[CallService] Peer connection error: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────
  //  Public API — Initiate / Accept / End Calls
  // ──────────────────────────────────────────────

  /// Initiate a call to another user.
  /// Creates a call record in Supabase, sets up WebRTC, and starts signaling.
  Future<CallInitResult> startCall({
    required String calleeId,
    String? orderId,
  }) async {
    final callerId = _currentUserId;
    if (callerId == null) {
      return const CallInitResult(error: 'Not authenticated');
    }

    final channelName = 'call-${DateTime.now().millisecondsSinceEpoch}-$callerId';

    try {
      // 1. Insert call record into Supabase
      final response = await SupabaseClientService.client.from('calls').insert({
        'caller_id': callerId,
        'callee_id': calleeId,
        'order_id': orderId,
        'status': 'CALLING',
        'channel_name': channelName,
      }).select().single();

      final call = Call.fromJson(Map<String, dynamic>.from(response));
      _currentCall = call;
      _isCaller = true;

      // 2. Subscribe to signaling channel
      _subscribeToSignaling(channelName);

      // 3. Create WebRTC peer connection and send offer
      final pc = await _createPeerConnection();
      if (pc == null) {
        return const CallInitResult(error: 'Failed to create connection');
      }

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // Small delay to ensure signaling channel is ready
      await Future.delayed(const Duration(milliseconds: 500));
      await _sendSignal({
        'type': 'offer',
        'sdp': offer.sdp,
      });

      _callController.add(call);

      // 5. Fire-and-forget: send FCM push notification to the callee
      //    (non-blocking — the call works without it)
      _sendCallPushNotification(
        calleeId: calleeId,
        callId: call.id,
        channelName: channelName,
      );

      return CallInitResult(success: true, call: call);
    } catch (e) {
      debugPrint('[CallService] Start call error: $e');
      return CallInitResult(error: 'Failed to start call: $e');
    }
  }

  /// Accept an incoming call.
  /// Updates the call status to CONNECTED and sets up WebRTC.
  Future<CallInitResult> acceptCall() async {
    final call = _currentCall;
    if (call == null) {
      return const CallInitResult(error: 'No incoming call');
    }

    try {
      // 1. Update call status to CONNECTED
      final now = DateTime.now().toIso8601String();
      await SupabaseClientService.client.from('calls').update({
        'status': 'CONNECTED',
        'started_at': now,
      }).eq('id', call.id);

      // 2. Subscribe to signaling channel
      _subscribeToSignaling(call.channelName);

      // 3. Create WebRTC peer connection (answer will be sent
      //    when the offer arrives via signaling)
      final pc = await _createPeerConnection();
      if (pc == null) {
        return const CallInitResult(error: 'Failed to create connection');
      }

      _isCaller = false;
      final updatedCall = Call(
        id: call.id,
        callerId: call.callerId,
        calleeId: call.calleeId,
        orderId: call.orderId,
        status: CallStatus.connected,
        channelName: call.channelName,
        startedAt: DateTime.tryParse(now),
        endedAt: null,
        durationSeconds: null,
        createdAt: call.createdAt,
      );
      _currentCall = updatedCall;
      _callController.add(updatedCall);

      return CallInitResult(success: true, call: updatedCall);
    } catch (e) {
      debugPrint('[CallService] Accept call error: $e');
      return CallInitResult(error: 'Failed to accept call: $e');
    }
  }

  /// Reject an incoming call.
  Future<void> rejectCall() async {
    final call = _currentCall;
    if (call == null) return;

    try {
      await SupabaseClientService.client.from('calls').update({
        'status': 'MISSED',
        'ended_at': DateTime.now().toIso8601String(),
      }).eq('id', call.id);

      _currentCall = null;
      _callController.add(null);
    } catch (e) {
      debugPrint('[CallService] Reject call error: $e');
    }
  }

  /// End the current call.
  Future<CallEndResult> endCall() async {
    await _hangUpWebRTC();

    final call = _currentCall;
    if (call == null || call.id.isEmpty) {
      return const CallEndResult(success: true);
    }

    final now = DateTime.now();
    final callDuration = call.startedAt != null
        ? now.difference(call.startedAt!).inSeconds
        : 0;

    try {
      await SupabaseClientService.client.from('calls').update({
        'status': 'ENDED',
        'ended_at': now.toIso8601String(),
        'duration_seconds': callDuration,
      }).eq('id', call.id);
    } catch (e) {
      debugPrint('[CallService] End call update error: $e');
    }

    _signalChannel?.unsubscribe();
    _currentCall = null;
    _callController.add(null);

    return CallEndResult(success: true, durationSeconds: callDuration);
  }

  /// Local cleanup when the remote peer disconnects.
  Future<void> _endCallLocally() async {
    await _hangUpWebRTC();
    _signalChannel?.unsubscribe();

    if (_currentCall != null) {
      final now = DateTime.now();
      final callDuration = _currentCall!.startedAt != null
          ? now.difference(_currentCall!.startedAt!).inSeconds
          : 0;

      final endedCall = _currentCall!;
      _currentCall = Call(
        id: endedCall.id,
        callerId: endedCall.callerId,
        calleeId: endedCall.calleeId,
        orderId: endedCall.orderId,
        status: CallStatus.ended,
        channelName: endedCall.channelName,
        startedAt: endedCall.startedAt,
        endedAt: now,
        durationSeconds: callDuration,
        createdAt: endedCall.createdAt,
      );

      _callController.add(_currentCall);
      onCallEnded?.call(CallEndResult(
        success: true,
        durationSeconds: callDuration,
      ));
      _currentCall = null;
    }
  }

  /// Tear down the WebRTC peer connection and local media stream.
  Future<void> _hangUpWebRTC() async {
    try {
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) => track.stop());
        _localStream!.dispose();
        _localStream = null;
      }
      if (_pc != null) {
        await _pc!.close();
        _pc = null;
      }
    } catch (e) {
      debugPrint('[CallService] Hangup error: $e');
    }

    _isMuted = false;
    _isSpeakerOn = false;
  }

  // ──────────────────────────────────────────────
  //  FCM Push Notification trigger
  // ──────────────────────────────────────────────

  /// Fire-and-forget: send an FCM push notification to the callee
  /// so they get an incoming call notification even if the app is
  /// backgrounded/terminated.
  Future<void> _sendCallPushNotification({
    required String calleeId,
    required String callId,
    required String channelName,
  }) async {
    final callerId = _currentUserId;
    if (callerId == null) return;

    try {
      // Get caller name from Supabase users table
      final callerRows = await SupabaseClientService.client
          .from('users')
          .select('username')
          .eq('id', callerId)
          .limit(1);
      final callerName =
          (callerRows.isNotEmpty ? callerRows.first['username'] as String? : null) ??
          'Caller';

      final dio = Dio(BaseOptions(baseUrl: SupabaseConfig.backendUrl));
      final token = await _getAuthToken();
      if (token == null) return;

      await dio.post(
        '/fcm/notify-call',
        data: {
          'calleeId': calleeId,
          'callerName': callerName,
          'callId': callId,
          'channelName': channelName,
        },
        options: Options(headers: {
          'Authorization': 'Bearer $token',
        }),
      );
    } catch (e) {
      // Non-blocking — the call works via Realtime without FCM
      debugPrint('[CallService] FCM trigger error (non-fatal): $e');
    }
  }

  /// Get the current user's auth token from Supabase session.
  Future<String?> _getAuthToken() async {
    try {
      final session = SupabaseClientService.client.auth.currentSession;
      return session?.accessToken;
    } catch (_) {
      return null;
    }
  }

  // ──────────────────────────────────────────────
  //  External trigger for incoming calls (from FCM)
  // ──────────────────────────────────────────────

  /// Called by [PushNotificationService] when an incoming call FCM
  /// payload is received (app was in background or terminated).
  /// Sets up the call state so the UI can navigate to IncomingCallScreen.
  void triggerIncomingCall(Call call) {
    _currentCall = call;
    _isCaller = false;
    _callController.add(call);
    onIncomingCall?.call(call);
  }

  // ── Mute / Speaker ──

  /// Toggle microphone mute.
  Future<void> toggleMute() async {
    if (_localStream == null) return;
    _isMuted = !_isMuted;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !_isMuted;
    }
    _muteController.add(_isMuted);
  }

  /// Toggle speakerphone on/off.
  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    try {
      await webrtc.Helper.selectAudioOutput(
        _isSpeakerOn ? 'speaker' : 'earpiece',
      );
    } catch (e) {
      debugPrint('[CallService] Speaker toggle error: $e');
    }
    _speakerController.add(_isSpeakerOn);
  }

  // ──────────────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────────────

  static DateTime? _parseDateTime(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
