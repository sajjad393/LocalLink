import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/domain/call_repository_contract.dart';
import 'package:locallink/features/calls/domain/call_gateway.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' hide CallState;

class _FakeGateway implements CallGateway {
  final _sessions = StreamController<CallSession?>.broadcast();
  final _history = StreamController<List<CallRecord>>.broadcast();
  CallSession? current;
  List<CallRecord> records = const [];
  bool started = false;
  bool shouldFailStartCall = false;

  @override
  Stream<CallSession?> get sessionStream => _sessions.stream;

  @override
  Stream<List<CallRecord>> get historyStream => _history.stream;

  @override
  CallSession? get session => current;

  @override
  String? get selfDeviceId => 'self';

  @override
  void start() => started = true;

  @override
  Future<void> syncHistory() async {
    _history.add(records);
  }

  @override
  Future<List<CallRecord>> history() async => records;

  @override
  Future<void> startCall(Device device) async {
    if (shouldFailStartCall) throw StateError('start failed');
    current = CallSession(
      id: 'call-1',
      peerId: device.id,
      peerName: device.name,
      direction: CallDirection.outgoing,
      state: CallState.ringing,
      startedAt: DateTime.utc(2026, 9, 21),
    );
    _sessions.add(current);
  }

  @override
  Future<void> acceptIncoming() async {}

  @override
  Future<void> rejectIncoming({String reason = 'rejected'}) async {}

  @override
  Future<void> endCall({String reason = 'hangup'}) async {}

  @override
  Future<void> toggleMute() async {}

  @override
  Future<void> toggleVideo() async {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> toggleSpeaker() async {}

  @override
  void onAppLifecycleState(_) {}

  @override
  Future<void> dispose() async {
    await _sessions.close();
    await _history.close();
  }
}

class _FakeRepository implements CallRepositoryContract {
  List<CallRecord> records = const [];
  Map<String, String> names = const {};

  @override
  Future<List<CallRecord>> history() async => records;

  @override
  Future<List<CallRecord>> syncHistory() async => records;

  @override
  Future<Map<String, String>> loadDeviceNames() async => names;
}

void main() {
  test('controller owns gateway lifecycle and mirrors call state', () async {
    final gateway = _FakeGateway();
    final controller = CallBloc(
      service: gateway,
      repository: _FakeRepository(),
    );

    controller.start();
    expect(gateway.started, isTrue);

    await controller.startCall(
      const Device(
        id: 'peer-1',
        name: 'Peer',
        platform: 'android',
        createdAt: '',
        lastSeenAt: '',
      ),
    );

    expect(controller.session?.id, 'call-1');
    expect(controller.session?.peerId, 'peer-1');

    await controller.close();
  });

  test('controller exposes action errors without losing state boundary',
      () async {
    final gateway = _FakeGateway()..shouldFailStartCall = true;
    final controller = CallBloc(
      service: gateway,
      repository: _FakeRepository(),
    );
    controller.start();

    await expectLater(
      controller.startCall(
        const Device(
          id: 'peer-1',
          name: 'Peer',
          platform: 'android',
          createdAt: '',
          lastSeenAt: '',
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(controller.error, isA<StateError>());

    controller.clearError();
    expect(controller.error, isNull);
    await controller.close();
  });
}
