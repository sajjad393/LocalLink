import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/features/groups/data/services/group_crypto_service.dart';

class ReliableMessagingService {
  final LocalStore store;
  final LocalLinkApi api;
  final WebSocketService socket;
  final FileTransferRepositoryContract files;
  final ConnectivityRepositoryContract connectivity;
  final PeerTransportContract directTransport;
  final IdentityCryptoService crypto;
  final GroupCryptoService groupCrypto;
  final _incoming = StreamController<Message>.broadcast();
  StreamSubscription? _socketSub;
  StreamSubscription? _connectionSub;
  StreamSubscription? _directSub;
  StreamSubscription? _wifiSub;
  Timer? _retryTimer;
  bool _syncing = false;
  bool _flushing = false;
  final Map<String, Map<String, dynamic>> _recentDirectFiles = {};
  final Set<String> _blockedIdentityPeers = <String>{};

  ReliableMessagingService(this.store, this.api, this.socket, this.files, this.connectivity, this.directTransport, this.crypto, this.groupCrypto);
  Stream<Message> get incoming => _incoming.stream;

  void start() {
    _socketSub ??= socket.messages.listen(_handleSocketMessage);
    _directSub ??= directTransport.events.listen(_handleDirectEvent);
    _wifiSub ??= connectivity.wifiDirectEvents.listen((_) => unawaited(_configureDirectTransport()));
    unawaited(_configureDirectTransport());
    _connectionSub ??= socket.connectionState.listen((connected) async {
      if (connected) { await synchronize(); await flush(); }
    });
    _retryTimer ??= Timer.periodic(const Duration(seconds: 5), (_) async {
      if (socket.isConnected) { await synchronize(); }
      await _configureDirectTransport();
      await flush();
    });
    if (store.serverAddress != null) { synchronize().then((_) => flush()); api.connectRealtime(); }
  }

  Future<void> send(String recipientId, String body, {List<PickedFile> attachments = const []}) async {
    if (await store.isBlockedPeer(recipientId)) throw Exception('This user is blocked');
    final id = _newId();
    final now = DateTime.now().toUtc();
    if (body.isEmpty && attachments.isEmpty) throw Exception('Message or attachment required');
    if (body.length > 16 * 1024) throw Exception('Message body must be 16KB or less');
    await store.addOutbox({'id': id, 'recipient_id': recipientId, 'body': body, 'created_at': now.toIso8601String(), 'status': 'queued'});
    final localAttachments = <Attachment>[];
    for (final file in attachments) {
      final fileId = _newId();
      await store.addPendingAttachment(id: fileId, messageId: id, file: file);
      localAttachments.add(Attachment(
        id: fileId,
        originalName: file.name,
        contentType: file.contentType,
        size: file.size,
        sha256: '',
        isImage: file.contentType.startsWith('image/'),
        localPath: file.path,
      ));
    }
    final message = Message(id: id, senderId: store.deviceId!, recipientId: recipientId, body: body, createdAt: now, status: 'queued', attachments: localAttachments);
    await store.saveMessage(message);
    _incoming.add(message);
    await flush();
  }

  Future<void> synchronize() async {
    if (_syncing || store.deviceToken == null || store.serverAddress == null) return;
    _syncing = true;
    try {
      await api.putIdentityKey(await crypto.publicKey());
      await refreshPeerKeys();
      var cursor = store.syncCursor;
      var hasMore = true;
      while (hasMore) {
        final page = await api.sync(cursor: cursor);
        for (final group in page.groups) {
          await store.saveGroup({'id': group.id, 'name': group.name, 'owner_id': group.ownerId, 'created_at': group.createdAt});
        }
        for (final member in page.groupMembers) {
          await store.saveGroupMember({'group_id': member.groupId, 'device_id': member.deviceId, 'role': member.role, 'joined_at': member.joinedAt, 'name': member.name});
        }
        for (final groupId in page.removedGroupIds) {
          final localPaths = await store.deleteGroupLocal(groupId);
          for (final path in localPaths) {
            await files.deleteLocalFile(path);
          }
        }
        final groupKeySync = <String>{};
        for (final groupMessage in page.groupMessages) {
          if (groupKeySync.add(groupMessage.groupId)) {
            await groupCrypto.syncGroupKeys(groupMessage.groupId);
          }
          final plaintext = await groupCrypto.decryptGroupMessage(groupMessage);
          if (plaintext == null) continue;
          await store.saveGroupMessage({
            'id': groupMessage.id, 'group_id': groupMessage.groupId, 'sender_id': groupMessage.senderId,
            'body': plaintext, 'created_at': groupMessage.createdAt, 'server_seq': groupMessage.serverSeq,
            'attachments': groupMessage.attachments.map((a) => a.toJson()).toList(),
          });
        }
        for (final networkMessage in page.messages) {
          final message = await _decryptMessageModel(networkMessage);
          if (message == null || await store.isBlockedPeer(message.senderId)) continue;
          final existed = await store.messageExists(message.id);
          await store.saveMessage(message);
          if (!existed &&
              message.recipientId == store.deviceId &&
              message.senderId != store.deviceId) {
            _incoming.add(message);
          }
          if (message.recipientId == store.deviceId && message.status != 'delivered') {
            try {
              final delivered = await api.acknowledgeMessage(message.id);
              await store.updateMessageStatus(delivered.id, status: delivered.status, deliveredAt: delivered.deliveredAt);
            } catch (_) {}
          }
          if (message.senderId == store.deviceId) {
            if (message.status == 'delivered') { await store.updateOutboxStatus(message.id, 'delivered'); await store.removeOutbox(message.id); }
            else { await store.updateOutboxStatus(message.id, 'sent'); }
          }
        }
        final next = page.nextCursor;
        if (next != null && next.isNotEmpty) { await store.saveSyncCursor(next); cursor = next; }
        hasMore = page.hasMore;
        if (page.hasMore && (next == null || next.isEmpty)) break;
      }
    } catch (_) {} finally { _syncing = false; }
  }

  Future<void> flush() async {
    if (_flushing || (!socket.isConnected && !directTransport.isStarted)) return;
    _flushing = true;
    try {
      final items = await store.outbox();
      for (final item in items) {
        final id = item['id'].toString();
        final status = item['status']?.toString() ?? 'queued';
        if (status == 'delivered') {
          await store.removeOutbox(id);
          continue;
        }
        if (status == 'direct_delivered' && !socket.isConnected) continue;

        final recipientId = item['recipient_id'].toString();
        final pending = await store.pendingAttachments(id);
        final canUseDirect = !socket.isConnected && directTransport.isStarted;
        if (canUseDirect) {
          try {
            final attachments = <Map<String, dynamic>>[];
            for (final attachment in pending) {
              final file = PickedFile(
                path: attachment['local_path'].toString(),
                name: attachment['original_name'].toString(),
                contentType: attachment['content_type'].toString(),
                size: int.tryParse(attachment['size'].toString()) ?? 0,
              );
              await files.sendDirectFile(
                recipientId: recipientId,
                messageId: id,
                fileId: attachment['id'].toString(),
                file: file,
              );
              attachments.add({
                'id': attachment['id'].toString(),
                'original_name': file.name,
                'content_type': file.contentType,
                'size': file.size,
                'sha256': '',
                'width': 0,
                'height': 0,
                'is_image': file.contentType.startsWith('image/'),
              });
            }
            final publicKeys = await crypto.cachedPeerPublicKeys();
          final derived = await crypto.derivePeerKeys(publicKeys);
          final shared = derived[recipientId];
          if (shared == null) throw StateError('peer encryption key unavailable');
          var encryptedBody = await store.outboxNetworkBody(id);
          encryptedBody ??= await crypto.encryptMessage(senderId: store.deviceId!, recipientId: recipientId, messageId: id, createdAt: item['created_at']?.toString() ?? '', plaintext: item['body']?.toString() ?? '', sharedKey: shared);
          await store.setOutboxNetworkBody(id, encryptedBody);
          await directTransport.send(
              recipientId: recipientId,
              payload: {
                'type': 'direct_message',
                'id': id,
                'sender_id': store.deviceId,
                'recipient_id': recipientId,
                'body': encryptedBody,
                'created_at': item['created_at'],
                if (attachments.isNotEmpty) 'attachments': attachments,
              },
            );
            await store.updateOutboxStatus(id, 'sending');
            await store.markOutboxAttempt(id);
          } catch (_) {}
          continue;
        }
        if (!socket.isConnected) continue;
        final remoteIds = <String>[];
        var uploadFailed = false;
        for (final attachment in pending) {
          final remote = attachment['remote_file_id']?.toString();
          if (remote != null && remote.isNotEmpty) {
            remoteIds.add(remote);
            continue;
          }
          try {
            final picked = PickedFile(
              path: attachment['local_path'].toString(),
              name: attachment['original_name'].toString(),
              contentType: attachment['content_type'].toString(),
              size: int.tryParse(attachment['size'].toString()) ?? 0,
            );
            final uploaded = await files.uploadE2eForMessage(picked, recipientId: recipientId, messageId: id, createdAt: item['created_at']?.toString() ?? '', clientFileId: attachment['id']?.toString() ?? '', operationId: id);
            await store.setPendingRemoteFile(attachment['id'].toString(), uploaded.id);
            remoteIds.add(uploaded.id);
          } catch (_) {
            uploadFailed = true;
            break;
          }
        }
        if (uploadFailed) continue;
        final publicKeys = await crypto.cachedPeerPublicKeys();
        final derived = await crypto.derivePeerKeys(publicKeys);
        final shared = derived[recipientId];
        if (shared == null) continue;
        var encryptedBody = await store.outboxNetworkBody(id);
        encryptedBody ??= await crypto.encryptMessage(senderId: store.deviceId!, recipientId: recipientId, messageId: id, createdAt: item['created_at']?.toString() ?? '', plaintext: item['body']?.toString() ?? '', sharedKey: shared);
        await store.setOutboxNetworkBody(id, encryptedBody);
        socket.send({
          'type': 'send_message',
          'id': id,
          'recipient_id': recipientId,
          'body': encryptedBody,
          if (remoteIds.isNotEmpty) 'attachment_ids': remoteIds,
        }, durable: true);
        await store.markOutboxAttempt(id);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<Message?> _decryptMessageModel(Message message) async {
    // The local device already has plaintext for messages it authored. Never try to
    // derive a peer key for self, otherwise sync/ack responses can be discarded.
    if (message.senderId == store.deviceId) {
      final local = await store.messageById(message.id);
      if (local != null) {
        return Message(
          id: local.id,
          senderId: local.senderId,
          recipientId: local.recipientId,
          body: local.body,
          createdAt: local.createdAt,
          status: message.status,
          deliveredAt: message.deliveredAt ?? local.deliveredAt,
          serverSeq: message.serverSeq > local.serverSeq ? message.serverSeq : local.serverSeq,
          attachments: message.attachments.isNotEmpty ? message.attachments : local.attachments,
        );
      }
      return null;
    }
    final peerPublic = (await crypto.cachedPeerPublicKeys())[message.senderId];
    if (peerPublic == null) return null;
    final shared = await crypto.deriveSharedKey(message.senderId, peerPublic);
    var body = await crypto.decryptMessage(senderId: message.senderId, recipientId: message.recipientId, messageId: message.id, createdAt: message.createdAt.toUtc().toIso8601String(), value: message.body, sharedKey: shared);
    if (body == null && message.body.startsWith('e2e:v2:')) {
      final history = await crypto.cachedPeerIdentityHistory();
      final candidates = history[message.senderId] ?? {1: peerPublic};
      body = await crypto.decryptMessageWithHistory(senderId: message.senderId, recipientId: message.recipientId, messageId: message.id, createdAt: message.createdAt.toUtc().toIso8601String(), value: message.body, peerKeysByVersion: candidates);
    }
    if (body == null && message.body.startsWith('e2e:v2:')) {
      final publicKeys = await crypto.cachedPeerPublicKeys();
      final history = await crypto.cachedPeerIdentityHistory();
      // Imported identity contexts belong to a replaced/previous device. The
      // peer-key candidates therefore must always be the *other* participant's
      // public keys, not the imported device's own historical keys.
      final senderCandidates = <int, String>{};
      senderCandidates.addAll(history[message.senderId] ?? const {});
      if (publicKeys[message.senderId] != null) senderCandidates[1] = publicKeys[message.senderId]!;
      final recipientCandidates = <int, String>{};
      recipientCandidates.addAll(history[message.recipientId] ?? const {});
      if (publicKeys[message.recipientId] != null) recipientCandidates[1] = publicKeys[message.recipientId]!;
      final importedSelfIsSender = (await crypto.importedIdentityKeyContexts()).containsKey(message.senderId);
      final importedCandidates = importedSelfIsSender ? recipientCandidates : senderCandidates;
      body = await crypto.decryptMessageWithIdentityContexts(
        senderId: message.senderId,
        recipientId: message.recipientId,
        messageId: message.id,
        createdAt: message.createdAt.toUtc().toIso8601String(),
        value: message.body,
        peerKeysByVersion: importedCandidates,
      );
    }
    if (body == null) {
      // Preserve legacy plaintext messages created before Phase 23.
      if (!message.body.startsWith('e2e:v1:')) return message;
      return null;
    }
    return Message(id: message.id, senderId: message.senderId, recipientId: message.recipientId, body: body, createdAt: message.createdAt, status: message.status, deliveredAt: message.deliveredAt, serverSeq: message.serverSeq, attachments: message.attachments);
  }

  Future<Message?> _decryptNetworkMessage(Map<String, dynamic> data) async {
    try {
      final message = Message.fromJson(data);
      if (message.senderId == store.deviceId) {
        final local = await store.messageById(message.id);
        if (local == null) return null;
        return Message(
          id: local.id,
          senderId: local.senderId,
          recipientId: local.recipientId,
          body: local.body,
          createdAt: local.createdAt,
          status: message.status,
          deliveredAt: message.deliveredAt ?? local.deliveredAt,
          serverSeq: message.serverSeq > local.serverSeq ? message.serverSeq : local.serverSeq,
          attachments: message.attachments.isNotEmpty ? message.attachments : local.attachments,
        );
      }
      final peerPublic = (await crypto.cachedPeerPublicKeys())[message.senderId];
      if (peerPublic == null) return null;
      final key = await crypto.deriveSharedKey(message.senderId, peerPublic);
      var body = await crypto.decryptMessage(senderId: message.senderId, recipientId: store.deviceId!, messageId: message.id, createdAt: message.createdAt.toUtc().toIso8601String(), value: message.body, sharedKey: key);
      if (body == null && message.body.startsWith('e2e:v2:')) {
        final history = await crypto.cachedPeerIdentityHistory();
        final candidates = history[message.senderId] ?? {1: peerPublic};
        body = await crypto.decryptMessageWithHistory(senderId: message.senderId, recipientId: store.deviceId!, messageId: message.id, createdAt: message.createdAt.toUtc().toIso8601String(), value: message.body, peerKeysByVersion: candidates);
      }
      if (body == null && message.body.startsWith('e2e:v2:')) {
        final publicKeys = await crypto.cachedPeerPublicKeys();
        final history = await crypto.cachedPeerIdentityHistory();
        final candidates = <int, String>{};
        candidates.addAll(history[message.senderId] ?? const {});
        if (publicKeys[message.senderId] != null) candidates[1] = publicKeys[message.senderId]!;
        body = await crypto.decryptMessageWithIdentityContexts(
          senderId: message.senderId,
          recipientId: store.deviceId!,
          messageId: message.id,
          createdAt: message.createdAt.toUtc().toIso8601String(),
          value: message.body,
          peerKeysByVersion: candidates,
        );
      }
      if (body == null) return null;
      return Message(id: message.id, senderId: message.senderId, recipientId: message.recipientId, body: body, createdAt: message.createdAt, status: message.status, deliveredAt: message.deliveredAt, serverSeq: message.serverSeq, attachments: message.attachments);
    } catch (_) { return null; }
  }

  Future<void> _handleSocketMessage(Map<String,dynamic> data) async {
    final type=data['type']?.toString();
    if(type=='error'){final id=data['id']?.toString();if(id!=null&&id.isNotEmpty)await store.updateOutboxStatus(id,'queued');return;}
    if(type=='message_ack'){
      final id=data['id']?.toString(); if(id==null||id.isEmpty)return;
      final pending=await store.pendingAttachments(id);
      final localPaths = pending.map((row) => row['local_path']?.toString()).whereType<String>().where((path) => path.isNotEmpty).toList();
      final existed=await store.messageExists(id);
      final base=await _decryptNetworkMessage(data); if(base==null)return;
      final atts=<Attachment>[];
      for(final attachment in base.attachments){
        atts.add(attachment);
      }
      final message=Message(id:base.id,senderId:base.senderId,recipientId:base.recipientId,body:base.body,createdAt:base.createdAt,status:base.status,deliveredAt:base.deliveredAt,serverSeq:base.serverSeq,attachments:atts);
      await store.updateOutboxStatus(id,data['status']?.toString()??'sent');await store.saveMessage(message);await store.removePendingAttachments(id);
      for (final path in localPaths) { await files.deleteLocalFile(path); }
      if (!existed) _incoming.add(message);return;
    }
    if(type=='delivery_ack'){final id=data['id']?.toString();if(id!=null&&id.isNotEmpty){final status=data['status']?.toString()??'delivered';await store.updateOutboxStatus(id,status);await store.updateMessageStatus(id,status:status,deliveredAt:data['created_at']?.toString());if(status=='delivered'||status=='direct_delivered'){await store.removeOutbox(id);}}return;}
    if(type!='message')return;
    try{final message=await _decryptNetworkMessage(data);if(message==null || await store.isBlockedPeer(message.senderId))return;await store.saveMessage(message);socket.send({'type':'ack_delivery','id':message.id});_incoming.add(message);}catch(_){ }
  }

  Future<void> _configureDirectTransport() async {
    if (store.deviceId == null) return;
    try {
      final info = await connectivity.wifiDirectConnectionInfo();
      final publicKeys = await crypto.cachedPeerPublicKeys();
      final keys = await crypto.derivePeerKeys(publicKeys);
      await directTransport.configure(
        deviceId: store.deviceId!,
        connected: info.connected,
        groupOwner: info.groupOwner,
        groupOwnerAddress: info.groupOwnerAddress,
        peerKeys: keys,
      );
    } catch (_) {}
  }

  Future<void> refreshPeerKeys() async {
    if (store.deviceToken == null || store.serverAddress == null) return;
    try {
      final records = await api.identityKeyRecords();
      final publicKeys = {for (final record in records) record.peerId: record.publicKey};
      final versions = {for (final record in records) record.peerId: record.keyVersion};
      final changedPeers = await crypto.cachePeerPublicKeys(publicKeys, versions: versions);
      _blockedIdentityPeers.addAll(changedPeers);
      try {
        await crypto.cachePeerIdentityHistory(await api.allIdentityKeyHistory());
      } catch (_) {}
      final cached = await crypto.cachedPeerPublicKeys();
      cached.removeWhere((id, _) => _blockedIdentityPeers.contains(id));
      final keys = await crypto.derivePeerKeys(cached);
      await directTransport.updatePeerKeys(keys);
      if (changedPeers.isNotEmpty) {
        throw StateError('peer identity changed without a newer key version: ${changedPeers.join(',')}');
      }
    } catch (_) {}
  }

  Future<void> _handleDirectEvent(Map<String, dynamic> event) async {
    final eventType = event['type']?.toString();
    if (eventType == 'file_received') {
      final fileId = event['file_id']?.toString();
      final messageId = event['message_id']?.toString();
      final path = event['path']?.toString();
      final senderId = event['sender_id']?.toString();
      if ([fileId, messageId, path, senderId].any((v) => v == null || v!.isEmpty)) return;
      if (await store.isBlockedPeer(senderId!)) return;
      final meta = <String, dynamic>{
        'file_id': fileId, 'message_id': messageId, 'path': path, 'sender_id': senderId,
        'original_name': event['file_name']?.toString() ?? 'attachment',
        'content_type': event['content_type']?.toString() ?? 'application/octet-stream',
        'size': int.tryParse(event['size']?.toString() ?? '') ?? 0,
        'sha256': event['sha256']?.toString() ?? '',
      };
      // Native direct-file reception uses app-private plaintext only as a short-lived
      // handoff. Convert it to Flutter's protected attachment format before persisting
      // the path in the local DB. Any crash before this handoff is bounded by the
      // native stale-file cleanup policy.
      final protectedPath = await files.protectLegacyLocalFile(path!);
      _recentDirectFiles[fileId!] = {...meta, 'path': protectedPath};
      await store.saveDirectFile(
        fileId: fileId, messageId: messageId!, senderId: senderId!, localPath: protectedPath,
        originalName: meta['original_name'] as String, contentType: meta['content_type'] as String,
        size: meta['size'] as int, sha256: meta['sha256'] as String,
      );
      final messages = await store.messagesFor(senderId);
      for (final message in messages.where((m) => m.id == messageId)) {
        final updated = message.copyWithMessageAttachments(await _attachmentsWithDirectFiles(message.attachments));
        await store.saveMessage(updated);
        _incoming.add(updated);
      }
      return;
    }
    if (eventType != 'message') return;
    // Only the final mesh recipient is allowed to surface a native mesh
    // message to the messaging/notification layers. Relay nodes emit only
    // mesh_forwarded/mesh_delivered telemetry and must never emit this event.
    if (event['mesh_final_recipient'] != true ||
        event['mesh_destination_id']?.toString() != store.deviceId) {
      return;
    }
    final raw = event['payload']?.toString();
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = data['type']?.toString();
      if (type == 'direct_message') {
        final decrypted = await _decryptNetworkMessage(data);
        if (decrypted == null) return;
        var message = decrypted;
        if (message.id.isEmpty || message.senderId.isEmpty || message.recipientId != store.deviceId || await store.isBlockedPeer(message.senderId)) return;
        final directAttachments = <Attachment>[];
        for (final attachment in message.attachments) {
          final stored = await store.directFile(attachment.id);
          if (stored != null) {
            directAttachments.add(attachment.copyWith(
              localPath: stored['local_path']?.toString(),
              sha256: stored['sha256']?.toString(),
              size: int.tryParse(stored['size']?.toString() ?? '') ?? attachment.size,
            ));
          } else {
            final recent = _recentDirectFiles[attachment.id];
            directAttachments.add(attachment.copyWith(
              localPath: recent?['path']?.toString(),
              sha256: recent?['sha256']?.toString(),
              size: recent?['size'] is int ? recent!['size'] as int : attachment.size,
            ));
          }
        }
        message = Message(id: message.id, senderId: message.senderId, recipientId: message.recipientId, body: message.body, createdAt: message.createdAt, status: 'delivered', deliveredAt: DateTime.now().toUtc().toIso8601String(), serverSeq: message.serverSeq, attachments: directAttachments);
        final existed = await store.messageExists(message.id);
        await store.saveMessage(message);
        try {
          await directTransport.send(recipientId: message.senderId, payload: {'type': 'direct_delivery_ack', 'id': message.id, 'sender_id': store.deviceId, 'recipient_id': message.senderId});
        } catch (_) {}
        if (!existed) _incoming.add(message);
        return;
      }
      if (type == 'direct_delivery_ack') {
        final id = data['id']?.toString();
        if (id == null || id.isEmpty || data['recipient_id']?.toString() != store.deviceId) return;
        final now = DateTime.now().toUtc();
        await store.updateOutboxStatus(id, 'direct_delivered');
        await store.updateMessageStatus(id, status: 'delivered', deliveredAt: now.toIso8601String());
        final senderId = data['sender_id']?.toString() ?? '';
        final local = (await store.messagesFor(senderId)).where((m) => m.id == id).toList();
        if (local.isNotEmpty && local.first.status != 'delivered') {
          _incoming.add(Message(id: local.first.id, senderId: local.first.senderId, recipientId: local.first.recipientId, body: local.first.body, createdAt: local.first.createdAt, status: 'delivered', deliveredAt: now.toIso8601String(), serverSeq: local.first.serverSeq, attachments: local.first.attachments));
        }
      }
    } catch (_) {}
  }

  Future<List<Attachment>> _attachmentsWithDirectFiles(List<Attachment> attachments) async {
    final out = <Attachment>[];
    for (final attachment in attachments) {
      final stored = await store.directFile(attachment.id);
      out.add(stored == null ? attachment : attachment.copyWith(localPath: stored['local_path']?.toString(), sha256: stored['sha256']?.toString(), size: int.tryParse(stored['size']?.toString() ?? '') ?? attachment.size));
    }
    return out;
  }

  Future<List<Message>> history(String otherId) async {
    final local=await store.messagesFor(otherId);
    await synchronize();
    try {
      final remote=await api.messages(otherId);
      for (final networkMessage in remote) {
        final message = await _decryptMessageModel(networkMessage);
        if (message != null && !await store.isBlockedPeer(message.senderId)) await store.saveMessage(message);
      }
      return await store.messagesFor(otherId);
    } catch (_) {
      return local;
    }
  }
  Future<void> dispose() async { _retryTimer?.cancel(); await _socketSub?.cancel(); await _connectionSub?.cancel(); await _directSub?.cancel(); await _wifiSub?.cancel(); await directTransport.dispose(); await _incoming.close(); }
  String _newId(){final random=Random.secure();final suffix=List.generate(12,(_)=>random.nextInt(16).toRadixString(16)).join();return '${DateTime.now().microsecondsSinceEpoch}-$suffix';}
}
