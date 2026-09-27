import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/call_quality.dart';

void main() {
  test('call quality sample round-trips', () {
    final sample = CallQualitySample(
      callId: 'call-1',
      sampledAt: DateTime.parse('2026-09-20T10:00:00Z'),
      connectionState: 'connected',
      transportState: 'connected',
      rttMs: 42,
      jitterMs: 3.5,
      packetsLost: 1,
      packetsReceived: 999,
      packetLossPercent: 0.1,
      quality: 'excellent',
    );
    final restored = CallQualitySample.fromDb(sample.toDb());
    expect(restored.callId, 'call-1');
    expect(restored.rttMs, 42);
    expect(restored.quality, 'excellent');
  });
}
