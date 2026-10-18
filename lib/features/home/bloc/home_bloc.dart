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

  /// Quiet, non-alarming line shown when the AUTOMATIC background sync cannot
  /// reach the server. Never louder, never red, never contains raw errors.
  final String? syncNotice;

  /// Best human-readable label per device id (directory display name first,
  /// then username). Conversation tiles show the person, not the device name.
  final Map<String, String> deviceLabels;

  const HomeState(
      {this.devices = const [],
      this.groups = const [],
      this.loading = true,
      this.error,
      this.syncNotice,
      this.deviceLabels = const {}});

  HomeState copyWith(
          {List<Device>? devices,
          List<LocalGroup>? groups,
          bool? loading,
          String? error,
          String? syncNotice,
          Map<String, String>? deviceLabels,
          bool clearError = false,
          bool clearSyncNotice = false}) =>
      HomeState(
        devices: devices ?? this.devices,
        groups: groups ?? this.groups,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        syncNotice: clearSyncNotice ? null : (syncNotice ?? this.syncNotice),
        deviceLabels: deviceLabels ?? this.deviceLabels,
      );

  @override
  List<Object?> get props => [devices, groups, loading, error, syncNotice, deviceLabels];
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
  String? get syncNotice => state.syncNotice;

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

  Future<void> load({bool userInitiated = false}) async {
    if (_closed) return;
    emit(state.copyWith(loading: true, clearError: true, clearSyncNotice: true));
    try {
      final rawDevices = await repository.devices();
      if (_closed) return;
      final groups = await repository.groups();
      if (_closed) return;
      final syncStamp = DateTime.now().toUtc().toIso8601String();
      bool wasReportedOnline(Device d) =>
          d.serverConnected || d.wifiDirectConnected || d.lanAvailable || d.meshAvailable;
      // The server's device list carries its own freshness: a peer the server
      // just saw alive is provisionally Online (60s window) until the first
      // live presence relay refreshes the stamp. Without this, every launch
      // would flash everyone Offline until the next 30s broadcast landed.
      final devices = rawDevices
          .map((d) => wasReportedOnline(d)
              ? d.copyWithPresence(presenceLocalAt: syncStamp)
              : d)
          .toList();
      for (final device in devices) {
        if (_closed) return;
        await repository.cacheDevice(device);
        if (wasReportedOnline(device)) {
          unawaited(repository.markDeviceSeen(device.id));
        }
      }
      if (_closed) return;
      _localDiscoveryAttempted = false;
      final visible = await _collapseDeviceDuplicates(
          devices.where((d) => d.id != repository.localDeviceId).toList());
      if (_closed) return;
      emit(state.copyWith(
        devices: visible,
        groups: groups,
        deviceLabels: await _labelsFor(visible),
        loading: false,
        clearError: true,
        clearSyncNotice: true,
      ));
    } catch (e) {
      if (_closed) return;
      try {
        final localDevices = await repository.localDevices();
        final localGroups = await repository.localGroups();
        if (_closed) return;
        final visible = await _collapseDeviceDuplicates(localDevices
            .where((d) => d.id != repository.localDeviceId)
            .toList());
        if (_closed) return;
        // A failing BACKGROUND sync is not an error worth a red banner: the
        // user sees their saved conversations plus a quiet offline line. Only
        // an explicit user action (pull-to-refresh, Retry) reports loudly.
        // No raw exception text in user-facing surfaces, ever. Explicit
        // Retry / pull-to-refresh earns ONE calm neutral chip; background
        // failures stay silent (saved conversations keep rendering and sync
        // retries itself) — matching how users expect a messenger to behave.
        final hasSavedData =
            localDevices.isNotEmpty || localGroups.isNotEmpty;
        emit(state.copyWith(
          devices: visible,
          groups: localGroups,
          deviceLabels: await _labelsFor(visible),
          error: null,
          syncNotice: userInitiated
              ? (hasSavedData
                  ? "Couldn't sync right now — showing your saved conversations."
                  : "Couldn't reach the server. Conversations will appear when it's back.")
              : null,
          loading: false,
        ));
      } catch (fallbackError) {
        if (!_closed) {
          emit(state.copyWith(
            error: null,
            syncNotice: userInitiated
                ? "Couldn't load your conversations. Please try again in a moment."
                : null,
            loading: false,
          ));
        }
      }
      await _startLocalDiscovery();
    }
  }

  /// Resolves conversation titles: the directory person's name wins over the
  /// raw device name, so "sana.oz" shows instead of "My Android Phone".
  Future<Map<String, String>> _labelsFor(List<Device> devices) async {
    final labels = <String, String>{};
    for (final device in devices) {
      String? label;
      try {
        label = await repository.labelForDevice(device.id);
      } catch (_) {
        label = null;
      }
      if (label != null && label.isNotEmpty) labels[device.id] = label;
    }
    return labels;
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
      final lan = data['lan_available'] == true;
      final mesh = data['mesh_available'] == true;
      _onPresence({
        'device_id': data['sender_id'],
        'network_status': (wifi || lan || mesh)
            ? 'orange'
            : server
                ? 'green'
                : 'red',
        'server_connected': server,
        'wifi_direct_connected': wifi,
        'lan_available': lan,
        'mesh_available': mesh,
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
      'lan_available': event['lan_available'] == true,
      'mesh_available': event['mesh_available'] == true,
      'status_updated_at': event['status_updated_at']?.toString() ?? '',
      // Liveness is stamped with OUR clock at arrival — the peer's
      // status_updated_at is display-only and never decides Online/Offline.
      'presence_local_at': DateTime.now().toUtc().toIso8601String(),
    });
    unawaited(repository.cacheDevice(updated));
    unawaited(_applyDeviceUpdate(updated));
  }

  Future<void> _applyDeviceUpdate(Device updated) async {
    if (_closed) return;
    final next = [...state.devices];
    final i = next.indexWhere((d) => d.id == updated.id);
    if (i < 0) {
      next.add(updated);
    } else {
      next[i] = updated;
    }
    final collapsed = await _collapseDeviceDuplicates(next);
    if (_closed) return;
    final labels = await _labelsFor(collapsed);
    if (!_closed) emit(state.copyWith(devices: collapsed, deviceLabels: labels));
  }

  /// Collapses multiple devices that belong to the same directory user into a
  /// single conversation entry, so one user never appears twice. Devices that
  /// cannot be resolved to a directory user are kept as-is.
  Future<List<Device>> _collapseDeviceDuplicates(List<Device> devices) async {
    final byUser = <String, Device>{};
    final standalone = <Device>[];
    for (final device in devices) {
      String? userId;
      try {
        userId = await repository.userIdForDevice(device.id);
      } catch (_) {
        userId = null;
      }
      if (userId == null || userId.isEmpty) {
        standalone.add(device);
        continue;
      }
      final current = byUser[userId];
      if (current == null || _isBetterConversationPeer(device, current)) {
        byUser[userId] = device;
      }
    }
    return [...byUser.values, ...standalone];
  }

  /// Picks which device should represent a user in the conversation list: an
  /// online device wins, otherwise the one seen most recently.
  static bool _isBetterConversationPeer(Device a, Device b) {
    bool online(Device d) => d.isOnline();
    if (online(a) != online(b)) return online(a);
    return a.lastSeenAt.compareTo(b.lastSeenAt) > 0;
  }

  /// Binary decay: a peer whose local liveness stamp slipped past the 60s
  /// window is Offline. Uses only locally-stamped arrival times — peer clock
  /// drift can no longer flip statuses in either direction.
  void expireStalePresence() {
    if (_closed) return;
    final now = DateTime.now().toUtc();
    var changed = false;
    final next = state.devices.map((device) {
      if (device.isOnline(now: now)) return device;
      final claimsReachable = device.serverConnected ||
          device.wifiDirectConnected ||
          device.lanAvailable ||
          device.meshAvailable;
      if (!claimsReachable) return device;
      changed = true;
      final stale = device.copyWithPresence(
        networkStatus: DeviceNetworkStatus.disconnected,
        serverConnected: false,
        wifiDirectConnected: false,
        lanAvailable: false,
        meshAvailable: false,
      );
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
