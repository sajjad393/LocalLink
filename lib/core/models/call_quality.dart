class CallQualitySample {
  final String callId;
  final DateTime sampledAt;
  final String connectionState;
  final String transportState;
  final double? rttMs;
  final double? jitterMs;
  final int packetsLost;
  final int packetsReceived;
  final double? packetLossPercent;
  final String quality;

  const CallQualitySample({
    required this.callId,
    required this.sampledAt,
    required this.connectionState,
    required this.transportState,
    this.rttMs,
    this.jitterMs,
    this.packetsLost = 0,
    this.packetsReceived = 0,
    this.packetLossPercent,
    required this.quality,
  });

  Map<String, dynamic> toDb() => {
        'call_id': callId,
        'sampled_at': sampledAt.toUtc().toIso8601String(),
        'connection_state': connectionState,
        'transport_state': transportState,
        'rtt_ms': rttMs,
        'jitter_ms': jitterMs,
        'packets_lost': packetsLost,
        'packets_received': packetsReceived,
        'packet_loss_percent': packetLossPercent,
        'quality': quality,
      };

  factory CallQualitySample.fromDb(Map<String, dynamic> row) => CallQualitySample(
        callId: row['call_id']?.toString() ?? '',
        sampledAt: DateTime.tryParse(row['sampled_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        connectionState: row['connection_state']?.toString() ?? 'unknown',
        transportState: row['transport_state']?.toString() ?? 'unknown',
        rttMs: _double(row['rtt_ms']),
        jitterMs: _double(row['jitter_ms']),
        packetsLost: int.tryParse(row['packets_lost']?.toString() ?? '') ?? 0,
        packetsReceived: int.tryParse(row['packets_received']?.toString() ?? '') ?? 0,
        packetLossPercent: _double(row['packet_loss_percent']),
        quality: row['quality']?.toString() ?? 'unknown',
      );

  static double? _double(Object? value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }
}
