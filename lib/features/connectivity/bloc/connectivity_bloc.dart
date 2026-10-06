import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/features/connectivity/data/models/connectivity_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/data/models/network_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/core/diagnostics/app_diagnostics.dart';

final class ConnectivityState extends Equatable {
  final ConnectivitySnapshot snapshot;
  final List<DiscoveredServer> servers;
  final bool busy;
  final bool isMonitoring;
  final String? error;

  const ConnectivityState({required this.snapshot, this.servers = const [], this.busy = false, this.isMonitoring = false, this.error});

  ConnectivityState copyWith({ConnectivitySnapshot? snapshot, List<DiscoveredServer>? servers, bool? busy, bool? isMonitoring, String? error, bool clearError = false}) => ConnectivityState(
        snapshot: snapshot ?? this.snapshot,
        servers: servers ?? this.servers,
        busy: busy ?? this.busy,
        isMonitoring: isMonitoring ?? this.isMonitoring,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [snapshot, servers, busy, isMonitoring, error];
}

final class ConnectivityBloc extends Cubit<ConnectivityState> {
  final ConnectivityRepositoryContract repository;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _started = false;
  bool _closed = false;

  ConnectivityBloc({required this.repository}) : super(ConnectivityState(snapshot: ConnectivitySnapshot.initial()));

  ConnectivitySnapshot get snapshot => state.snapshot;
  List<DiscoveredServer> get servers => state.servers;
  bool get busy => state.busy;
  String? get error => state.error;
  bool get isMonitoring => state.isMonitoring;

  Future<void> start() async {
    if (_started || _closed) return;
    _started = true;
    emit(state.copyWith(isMonitoring: true));
    _subscriptions.add(repository.serverConnectionState.listen((connected) {
      if (_closed) return;
      _update(snapshot.copyWith(serverConnected: connected));
      if (connected) unawaited(refresh());
    }));
    _subscriptions.add(repository.wifiDirectEvents.listen(_handleWifiEvent));
    _subscriptions.add(repository.wifiDirectTransportEvents.listen(_handleTransportEvent));
    _subscriptions.add(repository.networkChanges.listen(_handleNetworkChange));
    try {
      await repository.startMonitoring();
      if (_closed) return;
      await refresh();
    } catch (e) {
      if (!_closed) emit(state.copyWith(error: cleanBlocError(e)));
    }
  }

  Future<void> refresh() async {
    if (_closed) return;
    try {
      final next = await repository.refresh();
      if (_closed) return;
      _update(next);
      if (!_closed && state.error != null) emit(state.copyWith(clearError: true));
    } catch (e) {
      if (!_closed) emit(state.copyWith(error: cleanBlocError(e)));
    }
  }

  Future<List<DiscoveredServer>> discoverServers({Duration timeout = const Duration(seconds: 3), bool updateState = true}) async {
    if (_closed) return const [];
    try {
      final found = await repository.discoverServers(timeout: timeout);
      if (updateState && !_closed) emit(state.copyWith(servers: found, clearError: true));
      return found;
    } catch (e) {
      if (!_closed) emit(state.copyWith(error: cleanBlocError(e)));
      rethrow;
    }
  }

  Future<void> discoverWifiDirect() async {
    await _runBusy(() async {
      await repository.requestWifiDirectEnable();
      if (_closed) return;
      await repository.startWifiDirectDiscovery();
      if (_closed) return;
      await refresh();
    });
  }

  Future<void> connectWifiDirect(WifiDirectPeer peer) async {
    if (_closed) return;
    if (peer.address.trim().isEmpty) {
      emit(state.copyWith(error: 'This nearby phone cannot be connected right now.'));
      return;
    }
    await _runBusy(() => repository.connectWifiDirect(peer.address));
  }

  Future<void> disconnectWifiDirect() async {
    await _runBusy(() async {
      await repository.disconnectWifiDirect();
      if (_closed) return;
      await refresh();
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_closed || state.busy) return;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await action();
    } catch (e) {
      if (!_closed) emit(state.copyWith(error: cleanBlocError(e)));
    } finally {
      if (!_closed) emit(state.copyWith(busy: false));
    }
  }

  void _handleWifiEvent(dynamic event) {
    if (_closed || event is! Map) return;
    final type = event['type']?.toString();
    if (type == 'peers') {
      final raw = event['peers'];
      final peers = raw is List
          ? raw.whereType<Map>().map((p) => WifiDirectPeer.fromMap(Map<dynamic, dynamic>.from(p))).toList()
          : const <WifiDirectPeer>[];
      _update(snapshot.copyWith(wifiPeers: peers));
    } else if (type == 'connection') {
      final raw = event['connection'];
      if (raw is! Map) return;
      final connection = WifiDirectConnection.fromMap(Map<dynamic, dynamic>.from(raw));
      _update(snapshot.copyWith(
        wifiDirectConnected: connection.connected,
        wifiDirectGroupOwner: connection.groupOwner,
        wifiDirectConnection: connection,
      ));
      unawaited(_refreshTopologyOnly());
    }
  }

  void _handleTransportEvent(Map<String, dynamic> event) {
    if (_closed) return;
    final type = event['type']?.toString();
    if (type == 'topology' && event['device_id'] != null) {
      _update(snapshot.copyWith(topology: event));
      return;
    }
    if ({'peer_connected', 'peer_disconnected', 'mesh_queued', 'mesh_forwarded'}.contains(type)) {
      unawaited(_refreshTopologyOnly());
    }
  }

  void _handleNetworkChange(NetworkSnapshot network) {
    if (_closed) return;
    final changed = !snapshot.network.sameNetworkAs(network);
    _update(snapshot.copyWith(network: network));
    if (changed) unawaited(refresh());
  }

  Future<void> _refreshTopologyOnly() async {
    if (_closed) return;
    try {
      final topology = await repository.topology();
      if (!_closed) _update(snapshot.copyWith(topology: topology));
    } catch (_) {}
  }

  void _update(ConnectivitySnapshot next) {
    if (_closed) return;
    AppDiagnostics.instance.record(
      'connectivity',
      'snapshot',
      data: {
        'connected': next.network.connected,
        'transport': next.network.interfaceNames.isEmpty ? 'none' : 'lan',
      },
    );
    if (!_closed) emit(state.copyWith(snapshot: next.copyWith(updatedAt: DateTime.now().toUtc())));
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    if (_started) {
      _started = false;
      await repository.stopMonitoring();
    }
    await super.close();
  }
}
