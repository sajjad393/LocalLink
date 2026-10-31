import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

class WifiDirectTransportService implements PeerTransportContract {
  WifiDirectTransportService._();
  static final WifiDirectTransportService _instance = WifiDirectTransportService._();
  factory WifiDirectTransportService() => _instance;

  static const MethodChannel _channel = MethodChannel('locallink/wifi_direct_transport');
  static const EventChannel _events = EventChannel('locallink/wifi_direct_transport_events');

  Stream<Map<String, dynamic>>? _eventStream;
  bool _started = false;

  Stream<Map<String, dynamic>> get events => _eventStream ??= _events.receiveBroadcastStream().map((event) {
        if (event is Map) {
          final value = Map<String, dynamic>.from(event);
          if (value['type']?.toString() == 'state') {
            _started = value['transport_active'] == true || value['connected'] == true;
          }
          return value;
        }
        return <String, dynamic>{};
      });

  bool get isStarted => _started;

  Future<void> configure({
    required String deviceId,
    required bool connected,
    required bool groupOwner,
    String? groupOwnerAddress,
    required List<String> knownPeers,
  }) async {
    await _channel.invokeMethod('configure', {
      'device_id': deviceId,
      'connected': connected,
      'group_owner': groupOwner,
      'group_owner_address': groupOwnerAddress,
      'known_peers': knownPeers,
    });
    _started = true;
  }

  Future<void> updateKnownPeers(List<String> peerIds) => _channel.invokeMethod('updateKnownPeers', {'known_peers': peerIds});

  /// Bundle 156: blocked people are never accepted as relay links.
  Future<void> updateBlockedPeers(List<String> peerIds) =>
      _channel.invokeMethod('updateBlockedPeers', {'blocked_peers': peerIds});

  /// Bundle 160: per-contact link keys for the signed device id
  /// ({peerId: [{o, p, k}]}). Kept by the native side for the link hello.
  /// False when the native service was not running yet (try again later).
  Future<bool> updateLinkKeys(
    Map<String, List<Map<String, String>>> keys,
  ) async {
    final stored = await _channel.invokeMethod<Object?>(
      'updateLinkKeys',
      {'link_keys': jsonEncode(keys)},
    );
    return stored != false;
  }

  @override
  Future<void> ensureTransportReady({
    required String deviceId,
    List<String> knownPeers = const <String>[],
  }) async {
    await _channel.invokeMethod('ensureTransportReady', {
      'device_id': deviceId,
      'known_peers': knownPeers,
    });
    _started = true;
  }

  @override
  Future<void> sendPairPayload({required String nodeId, required String kind, required String body}) =>
      _channel.invokeMethod('sendPairPayload', {'target': nodeId, 'pair': kind, 'body': body});

  Future<Map<String, dynamic>> topology() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('topology') ?? const {};
    return Map<String, dynamic>.from(raw);
  }

  Future<void> flushQueue() => _channel.invokeMethod('flushQueue');

  Future<void> resume() async {
    await _channel.invokeMethod('resume');
    _started = true;
  }

  Future<void> clearStorage() => _channel.invokeMethod('clearStorage');

  Future<void> broadcast(Map<String, dynamic> payload) async {
    await _channel.invokeMethod('broadcast', {'payload': payload});
  }

  Future<void> send({required String recipientId, required Map<String, dynamic> payload}) async {
    await _channel.invokeMethod('send', {'recipient_id': recipientId, 'payload': payload});
  }

  Future<void> sendFile({
    required String recipientId,
    required String filePath,
    required String fileId,
    required String messageId,
    required String fileName,
    required String contentType,
  }) async {
    await _channel.invokeMethod('sendFile', {
      'recipient_id': recipientId,
      'file_path': filePath,
      'file_id': fileId,
      'message_id': messageId,
      'file_name': fileName,
      'content_type': contentType,
    });
  }

  @override
  Future<void> cancelFile(String fileId) => _channel.invokeMethod('cancelFile', {'file_id': fileId});

  Future<void> stop() async {
    _started = false;
    await _channel.invokeMethod('stop');
  }

  Future<void> dispose() async {}
}
