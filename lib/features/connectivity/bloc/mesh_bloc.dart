import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/connectivity/domain/mesh_repository_contract.dart';
import 'package:locallink/core/diagnostics/app_diagnostics.dart';

final class MeshPeer extends Equatable {
  final String nodeId;
  final String state;
  final String transport;
  final int? lastSeenAt;
  final int? connectedAt;

  const MeshPeer({required this.nodeId, required this.state, required this.transport, this.lastSeenAt, this.connectedAt});

  factory MeshPeer.fromMap(Map<String, dynamic> map) => MeshPeer(
        nodeId: map['node_id']?.toString() ?? map['peer_id']?.toString() ?? '',
        state: map['state']?.toString() ?? 'UNKNOWN',
        transport: map['transport']?.toString() ?? (map['direct'] == true ? 'wifi_direct' : 'unknown'),
        lastSeenAt: (map['last_seen_at'] as num?)?.toInt(),
        connectedAt: (map['connected_at'] as num?)?.toInt(),
      );

  @override
  List<Object?> get props => [nodeId, state, transport, lastSeenAt, connectedAt];
}

final class MeshRoute extends Equatable {
  final String destinationNodeId;
  final String nextHopNodeId;
  final int hopCount;
  final String state;
  final int? lastSeenAt;
  final int? expiresAt;
  final List<String> path;

  const MeshRoute({required this.destinationNodeId, required this.nextHopNodeId, required this.hopCount, required this.state, this.lastSeenAt, this.expiresAt, this.path = const []});

  factory MeshRoute.fromMap(Map<String, dynamic> map) => MeshRoute(
        destinationNodeId: map['destination']?.toString() ?? map['destination_node_id']?.toString() ?? map['destination_id']?.toString() ?? '',
        nextHopNodeId: map['next_hop']?.toString() ?? map['next_hop_node_id']?.toString() ?? map['next_hop_id']?.toString() ?? '',
        hopCount: (map['hop_count'] as num?)?.toInt() ?? (map['cost'] as num?)?.toInt() ?? 0,
        state: map['state']?.toString() ?? 'UNKNOWN',
        lastSeenAt: (map['last_seen_at'] as num?)?.toInt(),
        expiresAt: (map['expires_at'] as num?)?.toInt(),
        path: (map['path'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  @override
  List<Object?> get props => [destinationNodeId, nextHopNodeId, hopCount, state, lastSeenAt, expiresAt, path];
}

final class MeshState extends Equatable {
  final String? nodeId;
  final Map<String, MeshPeer> peers;
  final List<MeshRoute> routes;
  final int queuedPackets;
  final int queuedBytes;
  final int packetsSent;
  final int packetsReceived;
  final int sendFailures;
  final String? lastEvent;
  final String? error;

  const MeshState({this.nodeId, this.peers = const {}, this.routes = const [], this.queuedPackets = 0, this.queuedBytes = 0, this.packetsSent = 0, this.packetsReceived = 0, this.sendFailures = 0, this.lastEvent, this.error});

  MeshState copyWith({String? nodeId, Map<String, MeshPeer>? peers, List<MeshRoute>? routes, int? queuedPackets, int? queuedBytes, int? packetsSent, int? packetsReceived, int? sendFailures, String? lastEvent, String? error, bool clearError = false}) => MeshState(
        nodeId: nodeId ?? this.nodeId,
        peers: peers ?? this.peers,
        routes: routes ?? this.routes,
        queuedPackets: queuedPackets ?? this.queuedPackets,
        queuedBytes: queuedBytes ?? this.queuedBytes,
        packetsSent: packetsSent ?? this.packetsSent,
        packetsReceived: packetsReceived ?? this.packetsReceived,
        sendFailures: sendFailures ?? this.sendFailures,
        lastEvent: lastEvent ?? this.lastEvent,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [nodeId, peers, routes, queuedPackets, queuedBytes, packetsSent, packetsReceived, sendFailures, lastEvent, error];
}

final class MeshBloc extends Cubit<MeshState> {
  final MeshRepositoryContract repository;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  MeshBloc({required this.repository}) : super(const MeshState());

  Future<void> start() async {
    if (_subscription != null) return;
    _subscription = repository.events.listen(_handleEvent, onError: (Object error, StackTrace _) {
      emit(state.copyWith(error: error.toString()));
    });
    await refresh();
  }

  Future<void> refresh() async {
    try {
      await _applyTopology(await repository.topology());
      emit(state.copyWith(clearError: true));
    } catch (error) {
      emit(state.copyWith(error: error.toString()));
    }
  }

  Future<void> flushQueue() => repository.flushQueue();

  Future<void> send({required String recipientId, required Map<String, dynamic> payload}) =>
      repository.send(recipientId: recipientId, payload: payload);

  Future<void> _handleEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();
    if (type == 'topology' || event.containsKey('mesh_peers') || event.containsKey('routes')) {
      await _applyTopology(event);
    }
    if (type == null) return;
    AppDiagnostics.instance.record('mesh', type, data: {
      'peer_count': state.peers.length,
      'route_count': state.routes.length,
      'queue_packets': state.queuedPackets,
      'queue_bytes': state.queuedBytes,
      'packets_sent': state.packetsSent,
      'packets_received': state.packetsReceived,
      'send_failures': state.sendFailures,
      if (event['transport'] is String) 'transport': event['transport'].toString(),
      if (event['reason_code'] is String) 'reason_code': event['reason_code'].toString(),
    });
    var next = state.copyWith(lastEvent: type);
    final peerId = event['peer_id']?.toString().trim() ?? '';
    final routeDestination = event['destination_id']?.toString().trim() ?? '';
    switch (type) {
      case 'peer_discovered':
      case 'peer_connected':
      case 'peer_disconnected':
        if (peerId.isNotEmpty) {
          final stateName = switch (type) {
            'peer_discovered' => 'DISCOVERED',
            'peer_connected' => 'CONNECTED',
            _ => 'DISCONNECTED',
          };
          final peer = MeshPeer.fromMap({...event, 'node_id': peerId, 'state': stateName});
          final peers = Map<String, MeshPeer>.from(state.peers);
          peers[peerId] = peer;
          next = next.copyWith(peers: peers);
        }
        break;
      case 'route_changed':
      case 'route_recovered':
        if (routeDestination.isNotEmpty && event['next_hop_id'] != null) {
          final route = MeshRoute.fromMap({...event, 'destination_id': routeDestination, 'state': 'ACTIVE'});
          if (route.nextHopNodeId.isNotEmpty) {
            final routes = List<MeshRoute>.from(state.routes);
            routes.removeWhere((item) => item.destinationNodeId == route.destinationNodeId && item.nextHopNodeId == route.nextHopNodeId);
            routes.add(route);
            next = next.copyWith(routes: routes);
          }
        }
        break;
      case 'route_invalidated':
        final failedHop = event['failed_next_hop']?.toString().trim() ?? '';
        if (routeDestination.isNotEmpty && failedHop.isNotEmpty) {
          next = next.copyWith(routes: state.routes.where((route) => !(route.destinationNodeId == routeDestination && route.nextHopNodeId == failedHop)).toList(growable: false));
        }
        break;
      case 'route_removed':
        if (routeDestination.isNotEmpty) {
          next = next.copyWith(routes: state.routes.where((route) => route.destinationNodeId != routeDestination).toList(growable: false));
        }
        break;
      case 'mesh_queued':
        next = next.copyWith(queuedPackets: state.queuedPackets + 1);
        break;
      case 'mesh_expired':
      case 'mesh_retry_scheduled':
        break;
      case 'mesh_delivered':
        next = next.copyWith(packetsReceived: state.packetsReceived + 1);
        break;
      case 'mesh_forwarded':
        next = next.copyWith(packetsSent: state.packetsSent + 1);
        break;
      case 'mesh_dropped':
      case 'mesh_unroutable':
      case 'mesh_retry_exhausted':
        next = next.copyWith(sendFailures: state.sendFailures + 1, error: event['reason']?.toString() ?? type);
        break;
      case 'route_update':
        break;
    }
    emit(next);
  }

  Future<void> _applyTopology(Map<String, dynamic> topology) async {
    final peerList = _mapList(topology['mesh_peers'] ?? topology['peers']);
    final peers = <String, MeshPeer>{};
    for (final raw in peerList) {
      final peer = MeshPeer.fromMap(raw);
      if (peer.nodeId.isNotEmpty) peers[peer.nodeId] = peer;
    }
    final routeList = _mapList(topology['routes']);
    final routes = routeList.map(MeshRoute.fromMap).where((route) => route.destinationNodeId.isNotEmpty && route.nextHopNodeId.isNotEmpty).toList(growable: false);
    emit(state.copyWith(
      nodeId: topology['node_id']?.toString() ?? topology['device_id']?.toString() ?? state.nodeId,
      peers: peers,
      routes: routes,
      queuedPackets: (topology['queued_packets'] as num?)?.toInt() ?? state.queuedPackets,
      queuedBytes: (topology['queued_bytes'] as num?)?.toInt() ?? state.queuedBytes,
      packetsSent: (topology['packets_sent'] as num?)?.toInt() ?? state.packetsSent,
      packetsReceived: (topology['packets_received'] as num?)?.toInt() ?? state.packetsReceived,
      sendFailures: (topology['send_failures'] as num?)?.toInt() ?? state.sendFailures,
    ));
  }

  List<Map<String, dynamic>> _mapList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList(growable: false);
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    return super.close();
  }
}
