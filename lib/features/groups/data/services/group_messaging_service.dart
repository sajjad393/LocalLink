import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:locallink/core/models/message_reaction.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';

class GroupMessagingService {
  final LocalStore store;
  final LocalLinkApi api;
  final WebSocketService socket;
  final FileTransferRepositoryContract files;
  final _incoming = StreamController<GroupMessage>.broadcast();
  final _reactionIncoming = StreamController<MessageReaction>.broadcast();
  static const _reactionPrefix = 'llrx:v1:';
  StreamSubscription? _socketSub;
  StreamSubscription? _connectionSub;
  Timer? _retryTimer;
  bool _flushing = false;

  GroupMessagingService(this.store, this.api, this.socket, this.files);

  Stream<GroupMessage> get incoming => _incoming.stream;
  Stream<MessageReaction> get reactionIncoming => _reactionIncoming.stream;

  void start() {
    _socketSub ??= socket.messages.listen(_onMessage);
    _connectionSub ??= socket.connectionState.listen((connected) async {
      if (connected) await flush();
    });
    _retryTimer ??= Timer.periodic(const Duration(seconds: 5), (_) async {
      if (socket.isConnected) await flush();
    });
  }

  Future<List<GroupMessage>> history(String groupId) async {
    final local = (await store.groupMessages(groupId)).map((e) => GroupMessage.fromJson(e)).toList();
    try {
      final remote = await api.groupMessages(groupId);
      for (final m in remote) {
        if (await _consumeReaction(m)) continue;
        await store.saveGroupMessage(_messageMap(m));
      }
      return (await store.groupMessages(groupId)).map((e) => GroupMessage.fromJson(e)).toList();
    } catch (_) {
      return local;
    }
  }

  Future<void> sendReaction(String groupId, String messageId, String emoji) async {
    final normalized = emoji.trim();
    if (normalized.isEmpty || messageId.trim().isEmpty) throw const FormatException('Reaction is required');
    final id = _newId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final payload = jsonEncode({'message_id': messageId, 'emoji': normalized, 'reactor_id': store.deviceId, 'created_at': createdAt});
    await store.addGroupOutbox({'id': id, 'group_id': groupId, 'body': '$_reactionPrefix$payload', 'created_at': createdAt, 'status': 'queued'});
    await store.saveGroupMessageReaction(messageId: messageId, reactorId: store.deviceId ?? '', emoji: normalized, createdAt: createdAt);
    _reactionIncoming.add(MessageReaction(messageId: messageId, reactorId: store.deviceId ?? '', emoji: normalized, createdAt: DateTime.parse(createdAt).toLocal()));
    await flush();
  }

  Future<List<MessageReaction>> reactions(String messageId) async {
    final rows = await store.groupMessageReactions(messageId);
    return rows.map((row) => MessageReaction.fromJson(row)).toList(growable: false);
  }

  Future<GroupMessage> send(
    String groupId,
    String body, {
    List<PickedFile> attachments = const [],
  }) async {
    if (body.isEmpty && attachments.isEmpty) {
      throw Exception('Message or attachment required');
    }
    if (body.length > 16 * 1024) throw Exception('Message body is too large');
    final group = await store.groupById(groupId);
    if (group == null) throw Exception('Group not found');
    final id = _newId();
    final now = DateTime.now().toUtc().toIso8601String();
    await store.addGroupOutbox({
      'id': id,
      'group_id': groupId,
      'body': body,
      'created_at': now,
      'status': 'queued',
    });
    for (final file in attachments) {
      await store.addPendingGroupAttachment(id: _newId(), messageId: id, file: file);
    }
    final local = GroupMessage(
      id: id,
      groupId: groupId,
      senderId: store.deviceId ?? '',
      body: body,
      createdAt: now,
      serverSeq: 0,
    );
    await store.saveGroupMessage(_messageMap(local));
    _incoming.add(local);
    await flush();
    return local;
  }

  Future<void> flush() async {
    if (_flushing || !socket.isConnected) return;
    _flushing = true;
    try {
      final items = await store.groupOutbox();
      for (final item in items) {
        final id = item['id']?.toString() ?? '';
        final groupId = item['group_id']?.toString() ?? '';
        final createdAt = item['created_at']?.toString() ?? '';
        if (id.isEmpty || groupId.isEmpty || createdAt.isEmpty) continue;

        final body = item['body']?.toString() ?? '';

        final pending = await store.pendingGroupAttachments(id);
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
            final uploaded = await files.uploadForGroupMessage(picked, groupId: groupId, messageId: id, createdAt: createdAt, clientFileId: attachment['id']?.toString() ?? '', operationId: id);
            await store.setPendingGroupRemoteFile(attachment['id'].toString(), uploaded.id);
            remoteIds.add(uploaded.id);
          } catch (_) {
            uploadFailed = true;
            break;
          }
        }
        if (uploadFailed) continue;

        socket.send({
          'type': 'send_group_message',
          'id': id,
          'group_id': groupId,
          'body': body,
          'created_at': createdAt,
          if (remoteIds.isNotEmpty) 'attachment_ids': remoteIds,
        }, durable: true);
        await store.markGroupOutboxAttempt(id);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _consumeReaction(GroupMessage message) async {
    if (!message.body.startsWith(_reactionPrefix)) return false;
    try {
      final payload = jsonDecode(message.body.substring(_reactionPrefix.length));
      if (payload is! Map) return true;
      final messageId = payload['message_id']?.toString() ?? '';
      final emoji = payload['emoji']?.toString() ?? '';
      final reactorId = payload['reactor_id']?.toString() ?? message.senderId;
      final createdAt = payload['created_at']?.toString() ?? message.createdAt;
      if (messageId.isEmpty || emoji.isEmpty || reactorId != message.senderId) return true;
      await store.saveGroupMessageReaction(messageId: messageId, reactorId: reactorId, emoji: emoji, createdAt: createdAt);
      _reactionIncoming.add(MessageReaction(messageId: messageId, reactorId: reactorId, emoji: emoji, createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now()));
    } catch (_) {}
    return true;
  }

  Future<void> _onMessage(Map<String, dynamic> data) async {
    final type = data['type']?.toString();
    if (type == 'error') {
      final id = data['id']?.toString();
      if (id != null && id.isNotEmpty) await store.updateGroupOutboxStatus(id, 'queued');
      return;
    }
    if (type == 'group_message_ack') {
      final id = data['id']?.toString();
      if (id == null || id.isEmpty) return;
      final pending = await store.pendingGroupAttachments(id);
      final localPaths = pending.map((row) => row['local_path']?.toString()).whereType<String>().where((path) => path.isNotEmpty).toList();
      final base = GroupMessage.fromJson(data);
      final localRows = await store.groupMessages(base.groupId);
      final existing = localRows.map(GroupMessage.fromJson).where((m) => m.id == id).cast<GroupMessage?>().firstOrNull;
      if (existing == null && await _consumeReaction(base)) {
        await store.removeGroupOutbox(id);
        return;
      }
      final attachments = <Attachment>[];
      for (var i = 0; i < base.attachments.length; i++) {
        final localPath = i < pending.length ? pending[i]['local_path']?.toString() : null;
        attachments.add(base.attachments[i].copyWith(localPath: localPath));
      }
      final message = GroupMessage(
        id: base.id,
        groupId: base.groupId,
        senderId: base.senderId,
        body: existing?.body ?? base.body,
        createdAt: base.createdAt,
        serverSeq: base.serverSeq,
        attachments: attachments,
      );
      await store.saveGroupMessage(_messageMap(message));
      await store.removePendingGroupAttachments(id);
      await store.removeGroupOutbox(id);
      for (final path in localPaths) { await files.deleteLocalFile(path); }
      _incoming.add(message);
      return;
    }
    if (type != 'group_message') return;
    try {
      final message = GroupMessage.fromJson(data);
      if (await _consumeReaction(message)) return;
      if (await store.isBlockedPeer(message.senderId)) return;
      final existed = (await store.groupMessages(message.groupId)).any((m) => m['id']?.toString() == message.id);
      await store.saveGroupMessage(_messageMap(message));
      if (!existed) _incoming.add(message);
    } catch (_) {}
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    await _socketSub?.cancel();
    await _connectionSub?.cancel();
    await _reactionIncoming.close();
    await _incoming.close();
  }

  Map<String, dynamic> _messageMap(GroupMessage m) => {
        'id': m.id,
        'group_id': m.groupId,
        'sender_id': m.senderId,
        'body': m.body,
        'created_at': m.createdAt,
        'server_seq': m.serverSeq,
        'attachments': m.attachments.map((a) => a.toJson()).toList(),
      };

  String _newId() {
    final random = Random.secure();
    final suffix = List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
    return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }
}

extension on GroupMessage {
  GroupMessage copyWith({String? body}) => GroupMessage(
        id: id,
        groupId: groupId,
        senderId: senderId,
        body: body ?? this.body,
        createdAt: createdAt,
        serverSeq: serverSeq,
        attachments: attachments,
      );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
