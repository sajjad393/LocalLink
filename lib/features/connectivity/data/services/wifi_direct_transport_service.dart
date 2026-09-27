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
    required Map<String, String> peerKeys,
  }) async {
    await _channel.invokeMethod('configure', {
      'device_id': deviceId,
      'connected': connected,
      'group_owner': groupOwner,
      'group_owner_address': groupOwnerAddress,
      'peer_keys': peerKeys,
    });
    _started = true;
  }

  Future<void> updatePeerKeys(Map<String, String> peerKeys) => _channel.invokeMethod('updatePeerKeys', {'peer_keys': peerKeys});

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
