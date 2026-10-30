import 'dart:async';

import 'package:flutter/services.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';

export 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';

class WifiDirectService {
  WifiDirectService._();
  static final WifiDirectService _instance = WifiDirectService._();
  factory WifiDirectService() => _instance;

  static const _channel = MethodChannel('locallink/wifi_direct');
  static const _events = EventChannel('locallink/wifi_direct_events');
  Stream<dynamic>? _eventStream;

  Stream<dynamic> get events => _eventStream ??= _events.receiveBroadcastStream();

  Future<bool> isSupported() async =>
      await _channel.invokeMethod<bool>('isSupported') ?? false;

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermission') ?? false;
  Future<bool> isEnabled() async =>
      await _channel.invokeMethod<bool>('isEnabled') ?? false;
  Future<void> requestEnable() => _channel.invokeMethod('requestEnable');
  Future<void> startDiscovery() => _channel.invokeMethod('discoverPeers');

  Future<List<WifiDirectPeer>> getPeers() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('getPeers') ?? const [];
    return raw
        .map((e) => WifiDirectPeer.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
  }

  /// Bundle 155: intent 15 = want to host, 0 = want to join (was an invalid
  /// 50, so the host was random). A group member only leaves its group when
  /// [allowLeaveGroup] is true (a user's own tap).
  Future<void> connect(String address,
          {bool wantHost = false, bool allowLeaveGroup = true}) =>
      _channel.invokeMethod('connect', {
        'address': address,
        'intent': wantHost ? 15 : 0,
        'allowLeaveGroup': allowLeaveGroup,
      });

  /// Bundle 155: publish this phone's "who is who" tag id.
  Future<void> setNearbyIdentity(String tagId) =>
      _channel.invokeMethod('setNearbyIdentity', {'id': tagId});
  /// Bundle 157: one shared group.
  Future<void> setNearbyWanted(List<String> ids) =>
      _channel.invokeMethod('setNearbyWanted', {'ids': ids});
  Future<void> createNearbyGroup() =>
      _channel.invokeMethod('createNearbyGroup');
  /// Bundle 158: advertise `br=1` (this phone bridges its group and Wi-Fi).
  Future<void> setNearbyBridge(bool on) =>
      _channel.invokeMethod('setNearbyBridge', {'on': on});
  /// Bundle 167 (5.5): advertise `call=1` (a voice call goes on here).
  Future<void> setNearbyInCall(bool on) =>
      _channel.invokeMethod('setNearbyInCall', {'on': on});
  Future<void> joinNearbyGroup({
    String? name,
    String? key,
    required String address,
    bool leave = false,
  }) =>
      _channel.invokeMethod('joinNearbyGroup', {
        'name': name,
        'key': key,
        'address': address,
        'leave': leave,
      });
  /// Bundle 161: linked groups + LocalLink hotspot (tests).
  Future<String?> joinLocalNet({
    required String kind,
    required String ssid,
    required String key,
    String? v6,
  }) =>
      _channel.invokeMethod<String>('joinLocalNet', {
        'kind': kind,
        'ssid': ssid,
        'key': key,
        'v6': v6,
      });
  Future<void> leaveLocalNet(String reason) =>
      _channel.invokeMethod('leaveLocalNet', {'reason': reason});
  Future<String?> startLocalHotspot() =>
      _channel.invokeMethod<String>('startLocalHotspot');
  Future<void> stopLocalHotspot(String reason) =>
      _channel.invokeMethod('stopLocalHotspot', {'reason': reason});
  Future<void> setNearbyLinkTarget(String? id) =>
      _channel.invokeMethod('setNearbyLinkTarget', {'id': id});
  Future<void> cancelConnect() => _channel.invokeMethod('cancelConnect');
  Future<void> disconnect() => _channel.invokeMethod('disconnect');

  Future<WifiDirectConnection> connectionInfo() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'connectionInfo',
        ) ??
        const {};
    return WifiDirectConnection.fromMap(raw);
  }

  Future<void> dispose() async {}
}
