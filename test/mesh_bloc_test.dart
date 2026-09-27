import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/connectivity/domain/mesh_repository_contract.dart';

final class _FakeMeshRepository implements MeshRepositoryContract {
  final StreamController<Map<String, dynamic>> controller = StreamController.broadcast();
  Map<String, dynamic> currentTopology;

  _FakeMeshRepository([this.currentTopology = const {}]);

  @override
  Stream<Map<String, dynamic>> get events => controller.stream;

  @override
  Future<Map<String, dynamic>> topology() async => currentTopology;

  @override
  Future<void> flushQueue() async {}

  @override
  Future<void> send({required String recipientId, required Map<String, dynamic> payload}) async {}

  Future<void> close() => controller.close();
}

void main() {
  test('maps peer and route topology into typed mesh state', () async {
    final repo = _FakeMeshRepository({
      'node_id': 'A',
      'mesh_peers': [
        {'node_id': 'B', 'state': 'AVAILABLE', 'transport': 'lan', 'last_seen_at': 10},
      ],
      'routes': [
        {'destination': 'C', 'next_hop': 'B', 'hop_count': 2, 'state': 'ACTIVE'},
      ],
      'queued_packets': 1,
      'queued_bytes': 512,
    });
    final bloc = MeshBloc(repository: repo);
    await bloc.start();

    expect(bloc.state.nodeId, 'A');
    expect(bloc.state.peers['B']?.state, 'AVAILABLE');
    expect(bloc.state.routes.single.nextHopNodeId, 'B');
    expect(bloc.state.routes.single.hopCount, 2);
    expect(bloc.state.queuedPackets, 1);
    expect(bloc.state.queuedBytes, 512);

    await bloc.close();
    await repo.close();
  });

  test('consumes route and delivery events without socket access', () async {
    final repo = _FakeMeshRepository();
    final bloc = MeshBloc(repository: repo);
    await bloc.start();

    repo.controller.add({
      'type': 'topology',
      'node_id': 'A',
      'mesh_peers': [
        {'node_id': 'B', 'state': 'CONNECTED', 'transport': 'wifi_direct'},
      ],
      'routes': [
        {'destination': 'C', 'next_hop': 'B', 'hop_count': 2, 'state': 'ACTIVE'},
      ],
    });
    repo.controller.add({'type': 'mesh_delivered', 'packet_id': 'p1'});
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.peers['B']?.transport, 'wifi_direct');
    expect(bloc.state.lastEvent, 'mesh_delivered');

    await bloc.close();
    await repo.close();
  });
}
