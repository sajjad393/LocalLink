import 'dart:async';
import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';

final class HomeState extends Equatable {
  final List<Device> devices;
  final List<LocalGroup> groups;
  final bool loading;
  final String? error;

  const HomeState(
      {this.devices = const [],
      this.groups = const [],
      this.loading = true,
      this.error});

  HomeState copyWith(
          {List<Device>? devices,
          List<LocalGroup>? groups,
          bool? loading,
          String? error,
          bool clearError = false}) =>
      HomeState(
        devices: devices ?? this.devices,
        groups: groups ?? this.groups,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [devices, groups, loading, error];
}

final class HomeBloc extends Cubit<HomeState> {
  final HomeRepositoryContract repository;
  final Future<void> Function()? onServerSyncUnavailable;
  StreamSubscription<Map<String, dynamic>>? _presenceSub;
  StreamSubscription<Map<String, dynamic>>? _directPresenceSub;
  Timer? _statusTimer;
  bool _started = false;
  bool _closed = false;
  bool _localDiscoveryAttempted = false;

  HomeBloc({required this.repository, this.onServerSyncUnavailable})
      : super(const HomeState());

  List<Device> get devices => state.devices;
  List<LocalGroup> get groups => state.groups;
  bool get loading => state.loading;
  String? get error => state.error;

  void start() {
    if (_started || _closed) return;
    _started = true;
    _presenceSub = repository.presenceEvents.listen(_onPresence);
    _directPresenceSub =
        repository.directPresenceEvents.listen(_onDirectPresence);
    _statusTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => expireStalePresence());
    unawaited(load());
  }

  Future<void> load() async {
    if (_closed) return;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final devices = await repository.devices();
      if (_closed) return;
      final groups = await repository.groups();
      if (_closed) return;
      for (final device in devices) {
        if (_closed) return;
        await repository.cacheDevice(device);
      }
      if (_closed) return;
      _localDiscoveryAttempted = false;
      emit(state.copyWith(
        devices:
            devices.where((d) => d.id != repository.localDeviceId).toList(),
        groups: groups,
        loading: false,
        clearError: true,
      ));
    } catch (e) {
      if (_closed) return;
      try {
        final localDevices = await repository.localDevices();
        final localGroups = await repository.localGroups();
        if (_closed) return;
        emit(state.copyWith(
          devices: localDevices
              .where((d) => d.id != repository.localDeviceId)
              .toList(),
          groups: localGroups,
          error:
              '${localDevices.isEmpty && localGroups.isEmpty ? 'Server sync failed; no saved conversations are available.' : 'Server sync failed; showing saved conversations.'} ${cleanBlocError(e)}',
          loading: false,
        ));
      } catch (fallbackError) {
        if (!_closed) {
          emit(state.copyWith(
            error:
                'Server sync failed and saved conversations could not be loaded. ${cleanBlocError(e)}; local data error: ${cleanBlocError(fallbackError)}',
            loading: false,
          ));
        }
      }
      await _startLocalDiscovery();
    }
  }

  Future<void> _startLocalDiscovery() async {
    final startDiscovery = onServerSyncUnavailable;
    if (_closed || _localDiscoveryAttempted || startDiscovery == null) return;
    _localDiscoveryAttempted = true;
    await startDiscovery();
  }

  Future<LocalGroup?> createGroup(String name, List<String> memberIds) async {
    if (_closed) return null;
    try {
      final group = await repository.createGroup(name, memberIds);
      if (_closed) return null;
      emit(state.copyWith(groups: [...state.groups, group], clearError: true));
      return group;
    } catch (e) {
      if (!_closed) emit(state.copyWith(error: cleanBlocError(e)));
      return null;
    }
  }

  void _onDirectPresence(Map<String, dynamic> event) {
    if (_closed) return;
    final raw = event['payload']?.toString();
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['type']?.toString() != 'direct_presence') return;
      final server = data['server_connected'] == true;
      final wifi = data['wifi_direct_connected'] == true;
      _onPresence({
        'device_id': data['sender_id'],
        'network_status': wifi
            ? 'orange'
            : server
                ? 'green'
                : 'red',
        'server_connected': server,
        'wifi_direct_connected': wifi,
        'status_updated_at': data['status_updated_at']?.toString() ?? '',
      });
    } catch (_) {}
  }

  void _onPresence(Map<String, dynamic> event) {
    if (_closed) return;
    final id = event['device_id']?.toString();
    if (id == null || id.isEmpty) return;
    final current = state.devices.where((d) => d.id == id).isEmpty
        ? null
        : state.devices.firstWhere((d) => d.id == id);
    final base = current ??
        Device.fromJson({
          'id': id,
          'name': event['name']?.toString() ?? 'Nearby device',
          'platform': event['platform']?.toString() ?? 'android',
          'created_at': event['created_at']?.toString() ?? '',
          'last_seen_at': event['last_seen_at']?.toString() ?? '',
        });
    final updated = Device.fromJson({
      'id': base.id,
      'name': base.name,
      'platform': base.platform,
      'created_at': base.createdAt,
      'last_seen_at': event['last_seen_at']?.toString() ?? base.lastSeenAt,
      'network_status': event['network_status'],
      'server_connected': event['server_connected'] == true,
      'wifi_direct_connected': event['wifi_direct_connected'] == true,
      'status_updated_at': event['status_updated_at']?.toString() ?? '',
    });
    unawaited(repository.cacheDevice(updated));
    if (_closed) return;
    final next = [...state.devices];
    final i = next.indexWhere((d) => d.id == id);
    if (i < 0) {
      next.add(updated);
    } else {
      next[i] = updated;
    }
    emit(state.copyWith(devices: next));
  }

  void expireStalePresence() {
    if (_closed) return;
    final now = DateTime.now().toUtc();
    var changed = false;
    final next = state.devices.map((device) {
      final stamp = DateTime.tryParse(device.statusUpdatedAt)?.toUtc();
      if (stamp == null ||
          now.difference(stamp) <= const Duration(seconds: 40) ||
          device.networkStatus == DeviceNetworkStatus.unknown) {
        return device;
      }
      changed = true;
      final stale = Device.fromJson({
        'id': device.id,
        'name': device.name,
        'platform': device.platform,
        'created_at': device.createdAt,
        'last_seen_at': device.lastSeenAt,
        'network_status': 'unknown',
        'server_connected': false,
        'wifi_direct_connected': false,
        'status_updated_at': device.statusUpdatedAt,
      });
      unawaited(repository.cacheDevice(stale));
      return stale;
    }).toList();
    if (changed && !_closed) emit(state.copyWith(devices: next));
  }

  @override
  Future<void> close() async {
    _closed = true;
    _statusTimer?.cancel();
    await _presenceSub?.cancel();
    await _directPresenceSub?.cancel();
    return super.close();
  }
}
