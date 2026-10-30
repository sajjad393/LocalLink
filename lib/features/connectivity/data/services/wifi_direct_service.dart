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
