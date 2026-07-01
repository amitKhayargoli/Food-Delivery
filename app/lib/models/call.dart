/// Status of an in-app call session
enum CallStatus {
  calling('CALLING'),
  ringing('RINGING'),
  connected('CONNECTED'),
  ended('ENDED'),
  missed('MISSED');

  final String value;
  const CallStatus(this.value);

  static CallStatus fromString(String s) {
    return CallStatus.values.firstWhere(
      (e) => e.value == s,
      orElse: () => CallStatus.missed,
    );
  }
}

/// Represents an in-app call between two users.
class Call {
  final String id;
  final String callerId;
  final String calleeId;
  final String? orderId;
  final CallStatus status;
  final String channelName;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final DateTime createdAt;

  // Populated from users table via joins
  final String? callerName;
  final String? calleeName;
  final String? callerRole;
  final String? calleeRole;

  const Call({
    required this.id,
    required this.callerId,
    required this.calleeId,
    this.orderId,
    required this.status,
    required this.channelName,
    this.startedAt,
    this.endedAt,
    this.durationSeconds,
    required this.createdAt,
    this.callerName,
    this.calleeName,
    this.callerRole,
    this.calleeRole,
  });

  bool get isActive =>
      status == CallStatus.calling ||
      status == CallStatus.ringing ||
      status == CallStatus.connected;

  bool get isMeCaller => status == CallStatus.calling;

  factory Call.fromJson(Map<String, dynamic> json) {
    return Call(
      id: json['id'] as String? ?? '',
      callerId: json['caller_id'] as String? ?? '',
      calleeId: json['callee_id'] as String? ?? '',
      orderId: json['order_id'] as String?,
      status: CallStatus.fromString(json['status'] as String? ?? 'MISSED'),
      channelName: json['channel_name'] as String? ?? '',
      startedAt: _parseDateTime(json['started_at'] as String?),
      endedAt: _parseDateTime(json['ended_at'] as String?),
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      createdAt: _parseDateTime(json['created_at'] as String?) ?? DateTime.now(),
      callerName: json['caller_name'] as String?,
      calleeName: json['callee_name'] as String?,
      callerRole: json['caller_role'] as String?,
      calleeRole: json['callee_role'] as String?,
    );
  }

  static DateTime? _parseDateTime(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
