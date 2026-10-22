// Shared fakes and harnesses for the Phase 5 transport integration tests.
//
// Fakes stand in for platform boundaries (native peer transport, connectivity
// repository, secure crypto, file repository) while the real
// LocalRoutePolicyService, ReliableMessagingService and CallSessionManager run
// against them.

import 'dart:async';

import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/security/identity_trust_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_ringtone_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_notification_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_ringtone_service.dart';
import 'package:locallink/features/calls/data/services/call_session_manager.dart';
import 'package:locallink/features/calls/domain/call_repository_contract.dart';
import 'package:locallink/features/connectivity/data/models/connectivity_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/data/models/network_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';

/// In-memory stand-in for the native peer transport. Records everything that
/// would have been sent over the wire so tests can assert on behaviour.
class FakePeerTransport implements PeerTransportContract {
  bool started = true;
  Map<String, dynamic> topologyValue = const <String, dynamic>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];

  void emit(Map<String, dynamic> event) => _events.add(event);

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  bool get isStarted => started;

  @override
  Future<void> configure({
    required String deviceId,
    required bool connected,
    required bool groupOwner,
    String? groupOwnerAddress,
    required List<String> knownPeers,
  }) async {
    started = true;
  }

  @override
  Future<void> updateKnownPeers(List<String> peerIds) async {}

  @override
  Future<Map<String, dynamic>> topology() async => topologyValue;

  @override
  Future<void> flushQueue() async {}

  @override
  Future<void> resume() async {
    started = true;
  }

  @override
  Future<void> clearStorage() async {}

  @override
  Future<void> broadcast(Map<String, dynamic> payload) async {}

  @override
  Future<void> send({
    required String recipientId,
    required Map<String, dynamic> payload,
  }) async {
    sent.add(<String, dynamic>{
      'recipient_id': recipientId,
      ...payload,
    });
  }

  @override
  Future<void> sendFile({
    required String recipientId,
    required String filePath,
    required String fileId,
    required String messageId,
    required String fileName,
    required String contentType,
  }) async {}

  @override
  Future<void> cancelFile(String fileId) async {}

  @override
  Future<void> stop() async {
    started = false;
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

/// In-memory LocalStore. Only the outbox/messages/calls surface the services
/// under test use is implemented; untouched members keep the real behaviour,
/// which these tests never reach.
class FakeStore extends LocalStore {
  final List<Map<String, dynamic>> outboxItems = <Map<String, dynamic>>[];
  final Map<String, Message> messages = <String, Message>{};
  final List<CallRecord> savedCalls = <CallRecord>[];
  final List<Device> knownDevices = <Device>[];
  String selfId = 'self-device';

  @override
  String? get deviceId => selfId;

  @override
  bool get internetOnly => false;

  @override
  Future<List<Device>> localDevices() async =>
      List<Device>.unmodifiable(knownDevices);

  @override
  Future<bool> isBlockedPeer(String peerId) async => false;

  @override
  Future<void> addOutbox(Map<String, dynamic> item) async {
    outboxItems.add(Map<String, dynamic>.from(item));
  }

  @override
  Future<List<Map<String, dynamic>>> outbox({bool pendingOnly = false}) async {
    final items = pendingOnly
        ? outboxItems.where((item) {
            final status = item['status']?.toString() ?? 'queued';
            return status != 'delivered' && status != 'direct_delivered';
          })
        : outboxItems;
    return items.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  @override
  bool isOutboxRetryEligible(Map<String, dynamic> item, {DateTime? now}) =>
      true;

  @override
  Future<void> updateOutboxStatus(String id, String status) async {
    for (final item in outboxItems) {
      if (item['id']?.toString() == id) item['status'] = status;
    }
  }

  @override
  Future<void> markOutboxAttempt(String id) async {}

  @override
  Future<void> removeOutbox(String id) async {
    outboxItems.removeWhere((item) => item['id']?.toString() == id);
  }

  @override
  Future<List<Map<String, dynamic>>> pendingAttachments(
    String messageId,
  ) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<void> removePendingAttachments(String messageId) async {}

  @override
  Future<bool> messageExists(String id) async => messages.containsKey(id);

  @override
  Future<void> saveMessage(Message message) async {
    messages[message.id] = message;
  }

  @override
  Future<void> updateMessageStatus(
    String id, {
    String? status,
    String? deliveredAt,
  }) async {
    final existing = messages[id];
    if (existing == null) return;
    messages[id] = Message(
      id: existing.id,
      senderId: existing.senderId,
      recipientId: existing.recipientId,
      body: existing.body,
      createdAt: existing.createdAt,
      status: status ?? existing.status,
      deliveredAt: deliveredAt ?? existing.deliveredAt,
      serverSeq: existing.serverSeq,
      attachments: existing.attachments,
    );
  }

  @override
  Future<List<Message>> messagesFor(String otherId) async => messages.values
      .where((m) => m.senderId == otherId || m.recipientId == otherId)
      .toList();

  final Map<String, Map<String, dynamic>> directoryProfilesByDevice =
      <String, Map<String, dynamic>>{};
  final Set<String> contactUserIds = <String>{};

  @override
  Future<Map<String, dynamic>?> directoryProfileByDeviceId(
    String deviceId,
  ) async =>
      directoryProfilesByDevice[deviceId];

  @override
  Future<bool> isContact(String userId) async =>
      contactUserIds.contains(userId);

  @override
  Future<void> addContact(String userId, String deviceId) async {
    contactUserIds.add(userId);
  }

  final Map<String, Map<String, dynamic>> groupsById =
      <String, Map<String, dynamic>>{};
  final List<Map<String, dynamic>> groupOutboxItems =
      <Map<String, dynamic>>[];
  final Map<String, List<Map<String, dynamic>>> groupMessageRows =
      <String, List<Map<String, dynamic>>>{};

  @override
  Future<LocalGroup?> groupById(String groupId) async {
    final row = groupsById[groupId];
    if (row == null) return null;
    return LocalGroup(
      id: row['id']?.toString() ?? groupId,
      name: row['name']?.toString() ?? '',
      ownerId: row['owner_id']?.toString() ?? '',
      createdAt: row['created_at']?.toString() ?? '',
    );
  }

  @override
  Future<void> addGroupOutbox(Map<String, dynamic> item) async {
    groupOutboxItems.add(Map<String, dynamic>.from(item));
  }

  @override
  Future<List<Map<String, dynamic>>> groupOutbox() async =>
      groupOutboxItems.map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  Future<void> updateGroupOutboxStatus(String id, String status) async {
    for (final item in groupOutboxItems) {
      if (item['id']?.toString() == id) item['status'] = status;
    }
  }

  @override
  Future<void> markGroupOutboxAttempt(String id) async {}

  @override
  Future<void> removeGroupOutbox(String id) async {
    groupOutboxItems.removeWhere((i) => i['id']?.toString() == id);
  }

  @override
  Future<List<Map<String, dynamic>>> pendingGroupAttachments(
    String messageId,
  ) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<void> removePendingGroupAttachments(String messageId) async {}

  @override
  Future<void> saveGroupMessage(Map<String, dynamic> m) async {
    final list = groupMessageRows.putIfAbsent(
        m['group_id']?.toString() ?? '', () => <Map<String, dynamic>>[]);
    list.removeWhere((row) => row['id']?.toString() == m['id']?.toString());
    list.add(Map<String, dynamic>.from(m));
  }

  @override
  Future<List<Map<String, dynamic>>> groupMessages(String groupId) async =>
      (groupMessageRows[groupId] ?? const <Map<String, dynamic>>[])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  @override
  Future<void> saveCall(CallRecord call) async {
    savedCalls.removeWhere((c) => c.id == call.id);
    savedCalls.add(call);
  }

  Map<String, dynamic>? outboxEntry(String id) {
    for (final item in outboxItems) {
      if (item['id']?.toString() == id) return item;
    }
    return null;
  }
}

class FakeSocket extends WebSocketService {
  final _frames = StreamController<Map<String, dynamic>>.broadcast();
  final _state = StreamController<bool>.broadcast();
  bool connected = false;
  final List<Map<String, dynamic>> sentFrames = <Map<String, dynamic>>[];

  void emitFrame(Map<String, dynamic> frame) => _frames.add(frame);

  Future<void> goOnline() async {
    connected = true;
    _state.add(true);
  }

  Future<void> shutdown() async {
    await _frames.close();
    await _state.close();
  }

  @override
  Stream<Map<String, dynamic>> get messages => _frames.stream;

  @override
  Stream<bool> get connectionState => _state.stream;

  @override
  bool get isConnected => connected;

  @override
  bool send(Map<String, dynamic> payload, {bool durable = false}) {
    sentFrames.add(<String, dynamic>{...payload, 'durable': durable});
    return connected;
  }
}

class FakeConnectivity implements ConnectivityRepositoryContract {
  final _wifiEvents = StreamController<dynamic>.broadcast();

  @override
  Stream<bool> get serverConnectionState => const Stream<bool>.empty();

  @override
  Stream<dynamic> get wifiDirectEvents => _wifiEvents.stream;

  @override
  Stream<Map<String, dynamic>> get wifiDirectTransportEvents =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Stream<NetworkSnapshot> get networkChanges =>
      const Stream<NetworkSnapshot>.empty();

  @override
  Future<void> startMonitoring() async {}

  @override
  Future<void> stopMonitoring() async {}

  @override
  Future<List<DiscoveredServer>> discoverServers({Duration? timeout}) async =>
      const <DiscoveredServer>[];

  @override
  Future<bool> isWifiDirectSupported() async => false;

  @override
  Future<bool> isWifiDirectPermissionGranted() async => false;

  @override
  Future<void> requestWifiDirectEnable() async {}

  @override
  Future<void> startWifiDirectDiscovery() async {}

  @override
  Future<List<WifiDirectPeer>> wifiDirectPeers() async =>
      const <WifiDirectPeer>[];

  @override
  Future<WifiDirectConnection> wifiDirectConnectionInfo() async =>
      const WifiDirectConnection(
        connected: false,
        groupOwner: false,
        groupOwnerAddress: null,
      );

  @override
  Future<void> connectWifiDirect(String address) async {}

  @override
  Future<void> cancelWifiDirectConnect() async {}

  @override
  Future<void> disconnectWifiDirect() async {}

  @override
  Future<bool> isWifiDirectTransportStarted() async => false;

  @override
  Future<void> sendDirectFile({
    required String recipientId,
    required String filePath,
    required String fileId,
    required String messageId,
    required String fileName,
    required String contentType,
  }) async {}

  @override
  Future<void> cancelDirectFile(String fileId) async {}

  @override
  Future<Map<String, dynamic>> topology() async => const <String, dynamic>{};

  @override
  Future<ConnectivitySnapshot> refresh() => throw UnimplementedError();
}

class FakeFilesRepository implements FileTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unused in these tests: $invocation');

  @override
  Future<void> deleteLocalFile(String path) async {}

  @override
  Future<bool> isProtectedLocalFile(String path) async => true;

  @override
  Future<String> protectLegacyLocalFile(String plaintextPath) async =>
      plaintextPath;
}

class FakeCallRepository implements CallRepositoryContract {
  @override
  Future<List<CallRecord>> history() async => const <CallRecord>[];

  @override
  Future<List<CallRecord>> syncHistory() async => const <CallRecord>[];

  @override
  Future<Map<String, String>> loadDeviceNames() async =>
      const <String, String>{'peer-1': 'Peer One'};

  @override
  Future<String?> labelForPeer(String id) async => 'Peer One';
}

class AlwaysTrustedIdentity extends IdentityTrustService {
  @override
  Future<bool> canEstablishLocalCall(String deviceId) async => true;
}

// ---------------------------------------------------------------------------
// Topology helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> lanPeer(
  String peerId, {
  bool authenticated = true,
  List<String> transports = const <String>['lan'],
  String state = 'CONNECTED',
}) {
  return <String, dynamic>{
    'node_id': peerId,
    'direct': true,
    'authenticated': authenticated,
    'state': state,
    'last_seen_at': DateTime.now().millisecondsSinceEpoch,
    'available_transports': transports,
  };
}

Map<String, dynamic> meshRouteEntry(String peerId) {
  return <String, dynamic>{
    'destination': peerId,
    'state': 'ACTIVE',
    'expires_at':
        DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
    'next_hop_id': 'relay-1',
  };
}

Map<String, dynamic> outboxMessage(String id, String recipientId) {
  return <String, dynamic>{
    'id': id,
    'recipient_id': recipientId,
    'body': 'hello over locallink',
    'status': 'queued',
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'attempt_count': 0,
  };
}

Future<void> pumpEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

// ---------------------------------------------------------------------------
// Service harnesses
// ---------------------------------------------------------------------------

class MessagingHarness {
  MessagingHarness._(this.store, this.transport, this.policy, this.service);

  final FakeStore store;
  final FakePeerTransport transport;
  final LocalRoutePolicyService policy;
  final ReliableMessagingService service;

  static Future<MessagingHarness> create() async {
    final store = FakeStore();
    final transport = FakePeerTransport();
    final policy = LocalRoutePolicyService(transport);
    await policy.start();
    final service = ReliableMessagingService(
      store,
      LocalLinkApi(store, WebSocketService()),
      WebSocketService(),
      FakeFilesRepository(),
      FakeConnectivity(),
      transport,
      routePolicy: policy,
    );
    service.start();
    await pumpEvents();
    return MessagingHarness._(store, transport, policy, service);
  }

  Future<void> dispose() async {
    await service.dispose();
    await policy.dispose();
    await transport.dispose();
  }
}

class CallHarness {
  CallHarness._(this.store, this.transport, this.policy, this.manager);

  final FakeStore store;
  final FakePeerTransport transport;
  final LocalRoutePolicyService policy;
  final CallSessionManager manager;

  static Future<CallHarness> create() async {
    final store = FakeStore();
    final transport = FakePeerTransport();
    final policy = LocalRoutePolicyService(transport);
    await policy.start();
    final manager = CallSessionManager(
      store,
      transport,
      repository: FakeCallRepository(),
      audioPlatform: CallAudioPlatformService(),
      ringtone: CallRingtoneService(platform: CallRingtonePlatformService()),
      notificationPlatform: CallNotificationPlatformService(),
      mediaPlatform: CallMediaPlatformService(),
      identityTrust: AlwaysTrustedIdentity(),
      routePolicy: policy,
    );
    manager.start();
    await pumpEvents();
    return CallHarness._(store, transport, policy, manager);
  }

  Future<void> dispose() async {
    await manager.dispose();
    await policy.dispose();
    await transport.dispose();
  }
}
