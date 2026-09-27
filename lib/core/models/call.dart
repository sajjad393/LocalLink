class CallRecord {
  final String id;
  final String callerId;
  final String calleeId;
  final String status;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final String endReason;

  const CallRecord({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.status,
    required this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.endReason = '',
  });

  factory CallRecord.fromJson(Map<String, dynamic> json) => CallRecord(
        id: json['id']?.toString() ?? '',
        callerId: json['caller_id']?.toString() ?? '',
        calleeId: json['callee_id']?.toString() ?? '',
        status: json['status']?.toString() ?? 'ended',
        startedAt: DateTime.tryParse(json['started_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        answeredAt: DateTime.tryParse(json['answered_at']?.toString() ?? '')?.toLocal(),
        endedAt: DateTime.tryParse(json['ended_at']?.toString() ?? '')?.toLocal(),
        durationSeconds: int.tryParse(json['duration_seconds']?.toString() ?? '') ?? 0,
        endReason: json['end_reason']?.toString() ?? '',
      );

  factory CallRecord.fromDb(Map<String, dynamic> row) => CallRecord(
        id: row['id']?.toString() ?? '',
        callerId: row['caller_id']?.toString() ?? '',
        calleeId: row['callee_id']?.toString() ?? '',
        status: row['status']?.toString() ?? 'ended',
        startedAt: DateTime.tryParse(row['started_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        answeredAt: DateTime.tryParse(row['answered_at']?.toString() ?? '')?.toLocal(),
        endedAt: DateTime.tryParse(row['ended_at']?.toString() ?? '')?.toLocal(),
        durationSeconds: int.tryParse(row['duration_seconds']?.toString() ?? '') ?? 0,
        endReason: row['end_reason']?.toString() ?? '',
      );

  Map<String, dynamic> toDb() => {
        'id': id,
        'caller_id': callerId,
        'callee_id': calleeId,
        'status': status,
        'started_at': startedAt.toUtc().toIso8601String(),
        'answered_at': answeredAt?.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
        'end_reason': endReason,
      };

  String peerId(String selfId) => callerId == selfId ? calleeId : callerId;
  bool isOutgoing(String selfId) => callerId == selfId;
}
