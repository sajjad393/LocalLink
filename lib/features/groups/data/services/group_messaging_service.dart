import 'dart:async';
import 'package:locallink/core/services/media_book.dart';
import 'dart:math';
import 'dart:convert';
import 'package:locallink/core/models/message_reaction.dart';

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/messaging/data/message_delete_actions.dart';
import 'package:locallink/core/models/group_event.dart';
import 'package:locallink/features/groups/data/group_photo_book.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';
import 'package:locallink/features/groups/data/group_receipts.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipts_setting.dart';
import 'package:locallink/core/models/group_extras.dart';
import 'package:locallink/features/groups/data/group_extras_book.dart';
import 'package:locallink/features/groups/data/group_sender_keys.dart';
import 'package:locallink/features/groups/data/group_nearby_files.dart';
import 'package:locallink/features/files/data/services/media_transfer_actions.dart';
import 'package:crypto/crypto.dart' as hash;
import 'dart:io' show File;
import 'package:locallink/features/messaging/data/services/send_copy_book.dart';

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

  /// Bundle G3: Nearby groups (set once at start; null in old tests).
  GroupNearbyService? nearby;

  /// Bundle G6: end-to-end locks for the server road (null = off, old
  /// tests).
  GroupSenderKeys? senderKeys;

  /// Bundle G6: an invite-link request arrived (admins; may auto-add).
  Future<void> Function(String gid)? onJoinRequest;

  /// Bundle G3: one outgoing group message / reaction / delete note. It
  /// waits in the server outbox (a group only on phones keeps it there
  /// until the group is on the server = the sender's bridge) and, for a
  /// group with a card, also goes to every member Nearby when the server
  /// can't be reached right now.
  Future<void> _queue(Map<String, dynamic> row,
      {List<GroupNearbyFile> files = const []}) async {
    await store.addGroupOutbox(row);
    final near = nearby;
    final groupId = row['group_id']?.toString() ?? '';
    final body = row['body']?.toString() ?? '';
    // Bundle G7: a photo with no words goes Nearby too.
    final nearbyFiles = [
      for (final f in files)
        if (f.size <= GroupFileWire.maxBytes) f
    ];
    if (near == null || groupId.isEmpty) return;
    if (body.isEmpty && nearbyFiles.isEmpty) return;
    final group = await store.groupById(groupId);
    if (group == null || !group.worksNearby || !group.isActive) return;
    if (group.nearbyOnly || !socket.isConnected) {
      try {
        await near.fanOut(groupId, row['id'].toString(), body,
            row['created_at']?.toString() ?? '',
            files: nearbyFiles);
      } catch (error) {
        AppLogger.warning('GROUP_NEARBY_FANOUT_FAILED', detail: '$error');
      }
    }
  }

  /// Bundle G3: a member's message / reaction / delete note / system line
  /// that came Nearby.
  Future<void> receiveNearby(GroupMessage message) async {
    // Bundle G6: a locked copy (catch-up from a member) opens here too.
    if (GroupSenderKeys.isKeyNote(message.body)) return;
    message = await _open(message);
    if (await _consumeReaction(message)) return;
    if (!GroupEvent.isEvent(message.body) &&
        await store.isBlockedPeer(message.senderId)) {
      return;
    }
    final existed = (await store.groupMessageById(message.id)) != null;
    // Bundle G7: a file that came before its message.
    if (message.attachments.isNotEmpty) {
      message = await _withEarlyFiles(message);
    }
    await store.saveGroupMessage(_messageMap(message));
    if (!existed) _incoming.add(message);
    if (message.attachments.any((a) => (a.localPath ?? '').isEmpty)) {
      fileWatch.expect(message.id);
      unawaited(refreshFileKeys?.call().catchError((Object _) {}));
    }
    if (GroupEvent.isEvent(message.body)) {
      GroupChangeHub.instance.changed(message.groupId);
    }
  }

  // ------------------------------------------- Bundle G7: Nearby files

  /// Files that come to me Nearby but don't move: "Tap to download".
  final GroupFileWatch fileWatch = GroupFileWatch();

  /// Set at start: re-allows a file the user cancelled before (1:1 rule).
  Future<void> Function(String wireId)? allowIncomingFile;

  /// Set at start: stops a file coming to me.
  Future<void> Function(String wireId)? cancelIncomingFile;

  Future<GroupMessage> _withEarlyFiles(GroupMessage m) async {
    final self = store.deviceId ?? '';
    var changed = false;
    final out = <Attachment>[];
    for (final a in m.attachments) {
      if ((a.localPath ?? '').isNotEmpty) {
        out.add(a);
        continue;
      }
      final early = await store.directFile(GroupFileWire.wireId(a.id, self));
      final path = early?['local_path']?.toString() ?? '';
      if (path.isNotEmpty) {
        out.add(a.copyWith(localPath: path));
        changed = true;
      } else {
        out.add(a);
      }
    }
    if (!changed) return m;
    return GroupMessage(
        id: m.id,
        groupId: m.groupId,
        senderId: m.senderId,
        body: m.body,
        createdAt: m.createdAt,
        serverSeq: m.serverSeq,
        attachments: out,
        nearbySent: m.nearbySent);
  }

  /// A file for a group message came to me Nearby (after the 1:1 file code
  /// saved and locked it). [file]: file_id (wire id), message_id, path,
  /// sender_id, original_name, content_type, size.
  Future<bool> receiveNearbyFile(Map<String, dynamic> file) async {
    final wire = file['file_id']?.toString() ?? '';
    final messageId = file['message_id']?.toString() ?? '';
    final path = file['path']?.toString() ?? '';
    final sender = file['sender_id']?.toString() ?? '';
    final self = store.deviceId ?? '';
    if (!GroupFileWire.isWire(wire) || messageId.isEmpty || path.isEmpty) {
      return false;
    }
    if (!GroupFileWire.isFor(wire, self)) {
      AppLogger.warning('GROUP_FILE_RX_REFUSED', detail: 'why=not_mine');
      return true;
    }
    final fileId = GroupFileWire.fileIdOf(wire);
    if (GroupFileWire.isPhotoMessage(messageId)) {
      await _receivePhotoFile(messageId, fileId, path, sender);
      return true;
    }
    final message = await store.groupMessageById(messageId);
    if (message == null) {
      // Kept in direct_files; picked up when the message comes.
      AppLogger.info('GROUP_FILE_RX', detail: 'early=y');
      return true;
    }
    if (message.senderId != sender) {
      AppLogger.warning('GROUP_FILE_RX_REFUSED', detail: 'why=not_writer');
      return true;
    }
    final has = message.attachments.any((a) => a.id == fileId);
    if (has) {
      await store.setGroupAttachmentLocalPath(messageId, fileId, path);
    } else {
      // A copy from an old phone had no file list: add the file.
      final size = int.tryParse(file['size']?.toString() ?? '') ?? 0;
      final type = file['content_type']?.toString() ?? 'application/octet-stream';
      await store.saveGroupMessage(_messageMap(GroupMessage(
          id: message.id,
          groupId: message.groupId,
          senderId: message.senderId,
          body: message.body,
          createdAt: message.createdAt,
          serverSeq: message.serverSeq,
          nearbySent: message.nearbySent,
          attachments: [
            ...message.attachments,
            GroupNearbyFile(
                    id: fileId,
                    name: file['original_name']?.toString() ?? 'attachment',
                    type: type.contains('/') ? type : 'application/octet-stream',
                    size: size)
                .toAttachment(localPath: path),
          ])));
    }
    final updated = await store.groupMessageById(messageId);
    if (updated != null) {
      if (updated.attachments.every((a) => (a.localPath ?? '').isNotEmpty)) {
        fileWatch.done(messageId);
      } else {
        fileWatch.moved(messageId);
      }
      _incoming.add(updated);
    }
    AppLogger.info('GROUP_FILE_RX', detail: 'msg=${_short(messageId)}');
    return true;
  }

  static String _short(String id) =>
      id.length <= 6 ? id : id.substring(id.length - 6);

  /// Tap to download on a group file: ask the writer again (Nearby), or
  /// false when this is not a group message.
  Future<bool> requestFileAgain(String messageId, String attachmentId) async {
    final m = await store.groupMessageById(messageId);
    final near = nearby;
    if (m == null || near == null) return false;
    final self = store.deviceId ?? '';
    if (m.senderId == self) return false;
    try {
      await allowIncomingFile?.call(GroupFileWire.wireId(attachmentId, self));
    } catch (_) {}
    final ok = await near.sendFileNeed(m.groupId, m.id, attachmentId, m.senderId);
    if (ok) {
      MediaTransferActions.instance.clearCancelled(messageId);
      fileWatch.expect(messageId);
    }
    return ok;
  }

  /// X on a group file coming to me. False = not a group message.
  Future<bool> cancelFile(String messageId, String attachmentId) async {
    final m = await store.groupMessageById(messageId);
    if (m == null) return false;
    MediaTransferActions.instance.markCancelled(messageId);
    try {
      await cancelIncomingFile
          ?.call(GroupFileWire.wireId(attachmentId, store.deviceId ?? ''));
    } catch (_) {}
    return true;
  }

  /// The sender's own copy of a file (for [GroupFileSender]).
  Future<PickedFile?> fileSource(String msgId, String fileId) async {
    if (GroupFileWire.isPhotoMessage(msgId)) {
      final gid = GroupFileWire.photoGid(msgId);
      final v = GroupFileWire.photoVersion(fileId);
      final f = GroupPhotoBook.instance.fileFor(gid, v);
      if (f == null || !await f.exists()) return null;
      return PickedFile(
          path: f.path, name: 'group.jpg', contentType: 'image/jpeg', size: await f.length());
    }
    final m = await store.groupMessageById(msgId);
    String path = '';
    Attachment? att;
    for (final a in m?.attachments ?? const <Attachment>[]) {
      if (a.id == fileId) {
        att = a;
        path = a.localPath ?? '';
      }
    }
    if (path.isEmpty) {
      for (final row in await store.pendingGroupAttachments(msgId)) {
        if (row['id']?.toString() == fileId) {
          path = row['local_path']?.toString() ?? '';
        }
      }
    }
    if (att == null || path.isEmpty) return null;
    // Bundle 203 (3): one fixed open copy per group file (shared by all
    // members), so a retry continues instead of starting from 0. It is kept
    // for the other members and goes after 7 days (or with the message).
    final fixed = await SendCopyBook.instance.pathFor(
      localPath: path,
      fileId: att.id,
      originalName: att.originalName,
      open: (locked, ext) => files.materializeForDisplay(locked, extension: ext),
    );
    if (fixed != path && await File(fixed).exists()) {
      return PickedFile(
          path: fixed,
          name: att.originalName,
          contentType: att.contentType,
          size: att.size);
    }
    if (!await File(path).exists()) {
      // A locked copy: open it for sending (like 1:1).
      final locked = path.endsWith('.enc') ? path : '$path.enc';
      if (!await File(locked).exists()) return null;
      try {
        final ext = att.originalName.contains('.')
            ? '.${att.originalName.split('.').last}'
            : '.bin';
        path = await files.materializeForDisplay(locked, extension: ext);
      } catch (_) {
        return null;
      }
    }
    return PickedFile(
        path: path,
        name: att.originalName,
        contentType: att.contentType,
        size: att.size);
  }

  /// Sends one of my files to one member (the 1:1 file road).
  Future<void> sendFileTo({
    required String memberId,
    required String messageId,
    required String wireId,
    required PickedFile file,
  }) =>
      files.sendDirectFile(
          recipientId: memberId, messageId: messageId, fileId: wireId, file: file);

  /// A message of mine changed its file rows (ring / ticks).
  Future<void> fileRowsChanged(String messageId) async {
    if (GroupFileWire.isPhotoMessage(messageId)) return;
    final m = await store.groupMessageById(messageId);
    if (m != null) _incoming.add(m);
  }

  // ---------------------------------- Bundle G7: group photo, no internet

  static String _photoExpectKey(String gid) => 'gphoto_expect_$gid';
  static String _photoPendingKey(String gid) => 'gphoto_pending_$gid';

  /// An admin's signed photo note came (checked by the Nearby service).
  Future<bool> photoNote(String gid, int version, String hash, String by) async {
    final g = await store.groupById(gid);
    if (g == null || version <= g.photoVersion) return false;
    if (hash.isEmpty) {
      await store.saveGroup({'id': gid, 'photo_version': version});
      GroupPhotoBook.instance.forget(gid);
      GroupChangeHub.instance.changed(gid);
      AppLogger.info('GROUP_PHOTO_NEARBY', detail: 'removed v=$version');
      return true;
    }
    await store.writeSetting(_photoExpectKey(gid), '$version|$hash|$by');
    return true;
  }

  Future<void> _receivePhotoFile(
      String messageId, String fileId, String path, String sender) async {
    final gid = GroupFileWire.photoGid(messageId);
    final v = GroupFileWire.photoVersion(fileId);
    final expect = (await store.readSetting(_photoExpectKey(gid)) ?? '').split('|');
    String? view;
    try {
      if (expect.length != 3 || int.tryParse(expect[0]) != v || expect[2] != sender) {
        AppLogger.warning('GROUP_PHOTO_REFUSED', detail: 'why=not_expected');
        return;
      }
      List<int> bytes;
      if (await File(path).exists() && !path.endsWith('.enc')) {
        bytes = await File(path).readAsBytes();
      } else {
        view = await files.materializeForDisplay(path, extension: '.jpg');
        bytes = await File(view).readAsBytes();
      }
      if (bytes.length > 256 * 1024 ||
          hash.sha256.convert(bytes).toString() != expect[1]) {
        AppLogger.warning('GROUP_FILE_BAD_HASH', detail: 'photo=y');
        return;
      }
      final g = await store.groupById(gid);
      if (g == null || v <= g.photoVersion) return;
      await GroupPhotoBook.instance.put(gid, v, bytes);
      await store.saveGroup({'id': gid, 'photo_version': v});
      await store.writeSetting(_photoExpectKey(gid), '');
      GroupChangeHub.instance.changed(gid);
      AppLogger.info('GROUP_PHOTO_NEARBY', detail: 'got v=$v');
    } catch (error) {
      AppLogger.warning('GROUP_PHOTO_REFUSED', detail: 'why=$error');
    } finally {
      try {
        await files.deleteLocalFile(path);
        if (view != null) await files.deleteLocalFile(view);
      } catch (_) {}
    }
  }

  /// Bundle G7: set / remove the photo of a group made with no internet
  /// (the server gets it after the bridge).
  Future<void> setPhotoNearby(String gid, List<int>? jpeg) async {
    final near = nearby;
    final g = await store.groupById(gid);
    if (near == null || g == null) throw StateError('GROUP_NOT_FOUND');
    if (!await near.canSetPhoto(gid)) throw StateError('GROUP_NOT_ADMIN');
    final version = g.photoVersion + 1;
    if (jpeg == null) {
      await store.saveGroup({'id': gid, 'photo_version': version});
      GroupPhotoBook.instance.forget(gid);
      await store.writeSetting(_photoPendingKey(gid), 'removed');
      await near.sharePhoto(gid, version, '', 0);
    } else {
      await GroupPhotoBook.instance.put(gid, version, jpeg);
      await store.saveGroup({'id': gid, 'photo_version': version});
      await store.writeSetting(_photoPendingKey(gid), '$version');
      await near.sharePhoto(
          gid, version, hash.sha256.convert(jpeg).toString(), jpeg.length);
    }
    GroupChangeHub.instance.changed(gid);
  }

  /// After the bridge: the photo I set with no internet goes on the server.
  Future<void> uploadPendingPhotos() async {
    for (final g in await store.localGroups()) {
      if (g.nearbyOnly) continue;
      final pending = await store.readSetting(_photoPendingKey(g.id)) ?? '';
      if (pending.isEmpty) continue;
      try {
        if (pending == 'removed') {
          await api.removeGroupPhoto(g.id);
        } else {
          final f = GroupPhotoBook.instance.fileFor(g.id, int.tryParse(pending) ?? 0);
          if (f != null && await f.exists()) {
            final version = await api.setGroupPhoto(g.id, await f.readAsBytes());
            if (version > g.photoVersion) {
              await GroupPhotoBook.instance.put(g.id, version, await f.readAsBytes());
              await store.saveGroup({'id': g.id, 'photo_version': version});
            }
          }
        }
        await store.writeSetting(_photoPendingKey(g.id), '');
        AppLogger.info('GROUP_PHOTO_UPLOADED', detail: 'after=bridge');
      } catch (error) {
        AppLogger.warning('GROUP_PHOTO_UPLOAD_FAILED', detail: '$error');
      }
    }
  }

  /// Bundle G3: groups made on this phone (I own them) go on the server
  /// with the same id; then the outbox sends the waiting messages.
  Future<void> bridge() async {
    final near = nearby;
    if (near == null) return;
    try {
      final done = await near.bridge((card) async {
        final self = store.deviceId ?? '';
        final others = [
          for (final m in card.members)
            if (m.id != self) m.id
        ];
        final g = await api.createGroup(card.name, others,
            description: card.description,
            editInfo: card.editInfo,
            sendMessages: card.sendMessages,
            addMembers: card.addMembers,
            id: card.gid,
            bridge: true);
        if (g.id != card.gid) return false;
        for (final m in card.members) {
          if (m.role == 'admin') {
            try {
              await api.setGroupRole(card.gid, m.id, admin: true);
            } catch (_) {}
          }
        }
        return true;
      });
      if (done > 0) await flush();
    } catch (error) {
      AppLogger.warning('GROUP_BRIDGE_FAILED', detail: '$error');
    }
    // Bundle G7: a photo set with no internet goes on the server now.
    try {
      await uploadPendingPhotos();
    } catch (_) {}
  }

  /// Bundle G3: a quiet note through the server only (a group card for a
  /// group that is on the server too).
  Future<void> postControl(String groupId, String body) async {
    await store.addGroupOutbox({
      'id': _newId(),
      'group_id': groupId,
      'body': body,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'status': 'queued',
    });
    await flush();
  }

  /// Bundle G3: my message reached a member Nearby (bubble shows ✓).
  Future<void> sentNearby(String id) async {
    final message = await store.groupMessageById(id);
    if (message != null) _incoming.add(message);
  }

  /// Bundle 197a: delete for me / for everyone, clear chat.
  late final MessageDeleteActions deletes =
      MessageDeleteActions(store: store, deleteFile: files.deleteLocalFile);

  // Bundle 197a: deleted / cleared messages never reach the screen.
  Stream<GroupMessage> get incoming =>
      _incoming.stream.where((m) => !store.dropsGroupMessage(m));

  /// Bundle 197a: ids removed from this phone (the open chat drops them).
  Stream<String> get deletedMessageIds => store.deletedMessageIds;

  Future<void> deleteForMe(String id) => deletes.deleteForMe(id, group: true);

  /// Bundle 197a: only my own message, within 5 minutes. False = too late.
  Future<bool> deleteForEveryone(String groupId, String id) async {
    final message = await store.groupMessageById(id);
    final self = store.deviceId ?? '';
    if (message == null || self.isEmpty || groupId.isEmpty) return false;
    final created = DateTime.tryParse(message.createdAt);
    if (created == null ||
        !canDeleteForEveryone(mine: message.senderId == self, createdAt: created)) {
      return false;
    }
    final now = DateTime.now().toUtc();
    await deletes.deleteForEveryoneLocal(id, group: true, at: now);
    await _queue({
      'id': _newId(),
      'group_id': groupId,
      'body': DeleteCommand(messageId: id, by: self, at: now).encode(),
      'created_at': now.toIso8601String(),
      'status': 'queued',
    });
    AppLogger.info('MESSAGE_DELETE_ALL_SENT',
        detail: 'id=${MessageDeleteActions.shortId(id)} '
            'chat=${MessageDeleteActions.shortId(groupId)} group=y');
    await flush();
    return true;
  }

  Future<int> clearChat(String groupId) =>
      deletes.clearChat(chatId: groupId, group: true, keepRow: true);
  Stream<MessageReaction> get reactionIncoming => _reactionIncoming.stream;

  // ------------------------------------------------ Bundle G5 receipts

  final GroupTypingBook typingBook = GroupTypingBook();
  final _receiptChanges = StreamController<String>.broadcast();
  Stream<String> get receiptChanges => _receiptChanges.stream;

  void _bindReceiptHub() {
    GroupReceiptHub.load = (gid) async =>
        groupReceiptsByMessage(await store.groupReceipts(gid));
    GroupReceiptHub.changes = () => _receiptChanges.stream;
    GroupReceiptHub.markRead = markRead;
    GroupReceiptHub.refresh = pullReceipts;
    GroupReceiptHub.sendTyping = sendTyping;
    GroupReceiptHub.typing = typingBook.typing;
    GroupReceiptHub.typingChanges = () => typingBook.changes;
    _typingTickSub ??= typingBook.changes
        .listen((_) => GroupReceiptHub.typingVersion.value++);
  }

  StreamSubscription<String>? _typingTickSub;

  /// A member got / read one of my messages (server or Nearby).
  Future<void> recordReceipt(String gid, String messageId, String member,
      String status, {String at = ''}) async {
    final self = store.deviceId ?? '';
    if (gid.isEmpty || messageId.isEmpty || member.isEmpty || member == self) {
      return;
    }
    final when = at.isNotEmpty ? at : DateTime.now().toUtc().toIso8601String();
    try {
      await store.putGroupReceipt(messageId, gid, member,
          deliveredAt: status == 'delivered' ? when : '',
          readAt: status == 'read' ? when : '');
      _receiptChanges.add(gid);
    } catch (error) {
      AppLogger.warning('GROUP_RECEIPT_SAVE_FAILED', detail: '$error');
    }
  }

  bool _sendReceipt(String gid, List<String> ids, String status) {
    if (ids.isEmpty || !socket.isConnected) return false;
    return socket.send({
      'type': 'group_receipt',
      'group_id': gid,
      'status': status,
      'message_ids': ids,
    });
  }

  /// The group chat is open: every message from others not read yet is
  /// read now. "Read" goes to the writers only when my switch is on.
  Future<void> markRead(String gid) async {
    final self = store.deviceId ?? '';
    if (gid.isEmpty || self.isEmpty) return;
    final group = await store.groupById(gid);
    if (group == null) return;
    final have = groupReceiptsByMessage(await store.groupReceipts(gid));
    final unread = (await store.groupMessages(gid))
        .map(GroupMessage.fromJson)
        .where((m) =>
            m.senderId.isNotEmpty &&
            m.senderId != self &&
            GroupEvent.parse(m.body) == null &&
            have[m.id]?[self]?.readAt == null)
        .toList();
    if (unread.isEmpty) return;
    final list = unread.length > 200 ? unread.sublist(unread.length - 200) : unread;
    final on = ReadReceiptsSetting.instance.on;
    final now = DateTime.now().toUtc().toIso8601String();
    final serverIds = <String>[];
    final done = <GroupMessage>[];
    if (on && !group.nearbyOnly && socket.isConnected) {
      serverIds.addAll(list.where((m) => m.serverSeq > 0).map((m) => m.id));
      if (serverIds.isNotEmpty) _sendReceipt(gid, serverIds, 'read');
    }
    if (on && group.worksNearby && nearby != null) {
      final byWriter = <String, List<String>>{};
      for (final m in list) {
        (byWriter[m.senderId] ??= <String>[]).add(m.id);
      }
      for (final entry in byWriter.entries) {
        try {
          await nearby!.sendRead(gid, entry.key, entry.value);
        } catch (_) {}
      }
    }
    for (final m in list) {
      // A server-only message read while the server is away waits for the
      // next open (so the writer still gets "read").
      final waitsForServer = on &&
          !group.worksNearby &&
          m.serverSeq > 0 &&
          !serverIds.contains(m.id);
      if (!waitsForServer) done.add(m);
    }
    for (final m in done) {
      await store.putGroupReceipt(m.id, gid, self, deliveredAt: now, readAt: now);
    }
    if (done.isNotEmpty) {
      AppLogger.info('GROUP_READ',
          detail: 'n=${done.length} server=${serverIds.length} on=${on ? 'y' : 'n'}');
    }
  }

  /// Ask the server for receipts of my messages I may have missed.
  Future<void> pullReceipts(String gid) async {
    if (!socket.isConnected) return;
    final group = await store.groupById(gid);
    if (group == null || group.nearbyOnly) return;
    final key = 'group_rcpt_since_$gid';
    String since;
    try {
      since = await store.readSetting(key) ?? '';
    } catch (_) {
      since = '';
    }
    List<Map<String, dynamic>> rows;
    try {
      rows = await api.groupReceipts(gid, since: since);
    } catch (_) {
      return;
    }
    var last = since;
    for (final r in rows) {
      final mid = r['message_id']?.toString() ?? '';
      final dev = r['device_id']?.toString() ?? '';
      if (mid.isEmpty || dev.isEmpty) continue;
      await store.putGroupReceipt(mid, gid, dev,
          deliveredAt: r['delivered_at']?.toString() ?? '',
          readAt: r['read_at']?.toString() ?? '');
      final updated = r['updated_at']?.toString() ?? '';
      if (updated.compareTo(last) > 0) last = updated;
    }
    if (last != since) await store.writeSetting(key, last);
    if (rows.isNotEmpty) _receiptChanges.add(gid);
  }

  /// Back online: pull receipts and say "got it" for server messages that
  /// came while I could not tell.
  Future<void> receiptsCatchUp() async {
    final self = store.deviceId ?? '';
    if (self.isEmpty || !socket.isConnected) return;
    for (final row in await store.groups()) {
      final group = LocalGroup.fromJson(row);
      if (!group.isActive || group.nearbyOnly) continue;
      await pullReceipts(group.id);
      final have = groupReceiptsByMessage(await store.groupReceipts(group.id));
      final ids = (await store.groupMessages(group.id))
          .map(GroupMessage.fromJson)
          .where((m) =>
              m.serverSeq > 0 &&
              m.senderId.isNotEmpty &&
              m.senderId != self &&
              GroupEvent.parse(m.body) == null &&
              have[m.id]?[self] == null)
          .map((m) => m.id)
          .toList();
      if (ids.isEmpty) continue;
      final list = ids.length > 200 ? ids.sublist(ids.length - 200) : ids;
      if (_sendReceipt(group.id, list, 'delivered')) {
        final now = DateTime.now().toUtc().toIso8601String();
        for (final id in list) {
          await store.putGroupReceipt(id, group.id, self, deliveredAt: now);
        }
      }
    }
  }

  /// "I am typing" (server road only; at most one per 3 s from the composer).
  void sendTyping(String gid, bool on) {
    if (gid.isEmpty) return;
    unawaited(_sendTyping(gid, on));
  }

  /// Bundle G7: Nearby (live lock) when there is no server road.
  Future<void> _sendTyping(String gid, bool on) async {
    final group = await store.groupById(gid);
    final onServer = group == null || !group.nearbyOnly;
    if (socket.isConnected && onServer) {
      socket.send({'type': 'group_typing', 'group_id': gid, 'enabled': on});
      return;
    }
    final near = nearby;
    if (near == null || group == null || !group.worksNearby || !group.isActive) {
      return;
    }
    try {
      final n = await near.sendTyping(gid, on);
      if (on && n > 0 && _typingLogged.add(gid)) {
        AppLogger.info('GROUP_TYPING_NEARBY', detail: 'members=$n');
      }
    } catch (_) {}
  }

  final Set<String> _typingLogged = <String>{};

  /// Bundle G7: a member typing Nearby (same typing line as Online).
  Future<void> typingNearby(String gid, String member, bool on) async {
    if (member.isEmpty || member == (store.deviceId ?? '')) return;
    if (await store.isBlockedPeer(member)) return;
    typingBook.note(gid, member, on);
  }

  /// Bundle G7: set at start - pushes the pair file keys (so a file from a
  /// member who is not a friend can be opened).
  Future<void> Function()? refreshFileKeys;

  void start() {
    _socketSub ??= socket.messages.listen(_onMessage);
    _connectionSub ??= socket.connectionState.listen((connected) async {
      if (connected) {
        await bridge();
        await flush();
        unawaited(receiptsCatchUp().catchError((Object e) {
          AppLogger.warning('GROUP_RECEIPTS_CATCHUP_FAILED', detail: '$e');
        }));
        // Bundle G6: rows saved locked (sync) open when the key is here.
        unawaited(openLockedRows().catchError((Object e) {
          AppLogger.warning('GROUP_SK_REOPEN_FAILED', detail: '$e');
          return 0;
        }));
      }
    });
    _bindReceiptHub();
    _bindExtrasHub();
    nearby?.onReceipt = recordReceipt;
    nearby?.start();
    if (socket.isConnected) unawaited(bridge());
    _retryTimer ??= Timer.periodic(const Duration(seconds: 5), (_) async {
      if (socket.isConnected) await flush();
    });
  }

  Future<List<GroupMessage>> history(String groupId) async {
    final local = (await store.groupMessages(groupId)).map((e) => GroupMessage.fromJson(e)).toList();
    // Bundle G3: a group only on phones has nothing on the server yet.
    final group = await store.groupById(groupId);
    if (group != null && group.nearbyOnly) return local;
    try {
      final remote = await api.groupMessages(groupId);
      for (final raw in remote) {
        // Bundle G6: key notes; locked text opens here.
        if (await _consumeKeyNote(raw)) continue;
        final m = await _open(raw, ask: true);
        if (await _consumeReaction(m)) continue;
        if (await nearby?.consumeServerCard(m) ?? false) continue;
        await store.saveGroupMessage(_messageMap(m));
      }
      return (await store.groupMessages(groupId)).map((e) => GroupMessage.fromJson(e)).toList();
    } catch (_) {
      return local;
    }
  }

  Future<void> sendReaction(String groupId, String messageId, String emoji) async {
    final normalized = emoji.trim();
    if (messageId.trim().isEmpty) throw const FormatException('Reaction is required');
    if (normalized.isEmpty) {
      await _removeReaction(groupId, messageId);
      return;
    }
    final id = _newId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final payload = jsonEncode({'message_id': messageId, 'emoji': normalized, 'reactor_id': store.deviceId, 'created_at': createdAt});
    await _queue({'id': id, 'group_id': groupId, 'body': '$_reactionPrefix$payload', 'created_at': createdAt, 'status': 'queued'});
    await store.saveGroupMessageReaction(messageId: messageId, reactorId: store.deviceId ?? '', emoji: normalized, createdAt: createdAt);
    _reactionIncoming.add(MessageReaction(messageId: messageId, reactorId: store.deviceId ?? '', emoji: normalized, createdAt: DateTime.parse(createdAt).toLocal()));
    await flush();
  }

  /// Bundle G1 (mock 21): "Tap to remove" my reaction. Sent as the same
  /// llrx note with an empty emoji; older apps ignore an empty emoji.
  Future<void> _removeReaction(String groupId, String messageId) async {
    final id = _newId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final payload = jsonEncode({'message_id': messageId, 'emoji': '', 'reactor_id': store.deviceId, 'created_at': createdAt});
    await _queue({'id': id, 'group_id': groupId, 'body': '$_reactionPrefix$payload', 'created_at': createdAt, 'status': 'queued'});
    await store.deleteGroupMessageReaction(messageId: messageId, reactorId: store.deviceId ?? '');
    _reactionIncoming.add(MessageReaction(messageId: messageId, reactorId: store.deviceId ?? '', emoji: '', createdAt: DateTime.parse(createdAt).toLocal()));
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
    // Bundle G7: my own copy of each file in app storage (like 1:1), so my
    // bubble shows it at once and it can go to members Nearby.
    final mine = <Attachment>[];
    for (final file in attachments) {
      final pendingId = _newId();
      var staged = file;
      try {
        final path = await files.stageOutgoingFile(file: file, fileId: pendingId);
        staged = PickedFile(
            path: path,
            name: file.name,
            contentType: file.contentType,
            size: file.size,
            sourceUri: file.sourceUri);
      } catch (_) {}
      await store.addPendingGroupAttachment(id: pendingId, messageId: id, file: staged);
      // Bundle 197b: Gallery link + small picture (moved to the server's
      // file id when the group message is accepted).
      MediaBook.instance.staged(pendingId, staged.sourceUri, staged.path, staged.contentType, staged.name);
      mine.add(GroupNearbyFile(
              id: pendingId,
              name: staged.name,
              type: staged.contentType.contains('/')
                  ? staged.contentType
                  : 'application/octet-stream',
              size: staged.size)
          .toAttachment(localPath: staged.path));
    }
    final local = GroupMessage(
      id: id,
      groupId: groupId,
      senderId: store.deviceId ?? '',
      body: body,
      createdAt: now,
      serverSeq: 0,
      attachments: mine,
    );
    await store.saveGroupMessage(_messageMap(local));
    await _queue({
      'id': id,
      'group_id': groupId,
      'body': body,
      'created_at': now,
      'status': 'queued',
    }, files: [for (final a in mine) GroupNearbyFile.fromAttachment(a)]);
    _incoming.add(local);
    await flush();
    return local;
  }

  Future<void> flush() async {
    if (_flushing || !socket.isConnected) return;
    _flushing = true;
    final keysSent = <String>{};
    try {
      final items = await store.groupOutbox();
      for (final item in items) {
        final id = item['id']?.toString() ?? '';
        final groupId = item['group_id']?.toString() ?? '';
        final createdAt = item['created_at']?.toString() ?? '';
        if (id.isEmpty || groupId.isEmpty || createdAt.isEmpty) continue;
        // Bundle G2: nothing goes out from a group I left / was removed from.
        final group = await store.groupById(groupId);
        if (group != null && !group.isActive) continue;
        // Bundle G3: not on the server yet - it waits for the bridge.
        if (group != null && group.nearbyOnly) continue;

        final body = item['body']?.toString() ?? '';

        final pending = await store.pendingGroupAttachments(id);
        final remoteIds = <String>[];
        var uploadFailed = false;
        // Bundle G7 (P1): every member already got my files Nearby - no
        // upload (same as 1:1). Words still go; a photo alone stays local.
        var skipUpload = false;
        if (pending.isNotEmpty &&
            group != null &&
            group.worksNearby &&
            await _allHaveNearby(groupId, id, pending)) {
          if (body.isEmpty) {
            await store.removeGroupOutbox(id);
            await store.removePendingGroupAttachments(id);
            AppLogger.info('GROUP_FILE_UPLOAD_SKIPPED', detail: 'all_have=y words=n');
            continue;
          }
          skipUpload = true;
          AppLogger.info('GROUP_FILE_UPLOAD_SKIPPED', detail: 'all_have=y words=y');
        }
        for (final attachment in skipUpload ? const <Map<String, dynamic>>[] : pending) {
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

        // Bundle G6: the server gets only the locked text.
        var wire = body;
        if (_lockable(body)) {
          wire = await _lockForServer(groupId, id, body, keysSent) ?? body;
        }

        socket.send({
          'type': 'send_group_message',
          'id': id,
          'group_id': groupId,
          'body': wire,
          'created_at': createdAt,
          if (remoteIds.isNotEmpty) 'attachment_ids': remoteIds,
        }, durable: true);
        await store.markGroupOutboxAttempt(id);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _allHaveNearby(
      String gid, String id, List<Map<String, dynamic>> pending) async {
    final sender = nearby?.files;
    if (sender == null) return false;
    try {
      final c = await nearby!.card(gid);
      if (c == null) return false;
      final self = store.deviceId ?? '';
      return await sender.allDelivered(id, [
        for (final m in c.members)
          if (m.id != self) m.id
      ], fileIds: [
        for (final row in pending) row['id']?.toString() ?? ''
      ]);
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------- Bundle G6 sender keys

  final Map<String, DateTime> _asked = <String, DateTime>{};
  final Set<String> _plainLogged = <String>{};

  bool _lockable(String body) =>
      senderKeys != null &&
      body.isNotEmpty &&
      !body.startsWith(GroupNearbyService.cardBodyPrefix) &&
      !GroupSenderKeys.isKeyNote(body) &&
      !GroupSenderKeys.isLocked(body) &&
      !GroupEvent.isEvent(body);

  Future<List<String>> _otherMembers(String gid) async {
    final self = store.deviceId ?? '';
    try {
      return [
        for (final row in await store.groupMembers(gid))
          if ((row['device_id']?.toString() ?? '').isNotEmpty &&
              row['device_id'].toString() != self)
            row['device_id'].toString()
      ];
    } catch (_) {
      return const [];
    }
  }

  /// My key for [gid] with its note on the way (once per flush). Null =
  /// a member's public key is missing: the message goes as before.
  Future<GroupMyKey?> _keyReady(String gid, Set<String> keysSent) async {
    final sk = senderKeys;
    if (sk == null) return null;
    final members = await _otherMembers(gid);
    if (members.isEmpty) return null;
    final key = await sk.current(gid, members);
    if (key.distributed || keysSent.contains(gid)) return key;
    final note = await sk.keysNote(gid, key.kid, key.key, key.members);
    if (note == null) {
      if (_plainLogged.add(gid)) {
        AppLogger.warning('GROUP_SK_PLAIN', detail: 'reason=no_member_key');
      }
      return null;
    }
    final noteId = await sk.noteIdFor(gid, _newId);
    socket.send({
      'type': 'send_group_message',
      'id': noteId,
      'group_id': gid,
      'body': note,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, durable: true);
    keysSent.add(gid);
    AppLogger.info('GROUP_SK_KEYS_SENT', detail: 'n=${key.members.length}');
    return key;
  }

  Future<String?> _lockForServer(
      String gid, String id, String body, Set<String> keysSent) async {
    try {
      final key = await _keyReady(gid, keysSent);
      if (key == null) return null;
      return await senderKeys!.lock(gid, id, body, key);
    } catch (error) {
      AppLogger.warning('GROUP_SK_LOCK_FAILED', detail: '$error');
      return null;
    }
  }

  /// The open text of [m] (or [m] as it is). A locked message this phone
  /// can't open stays locked ("🔒 Waiting…") and, with [ask], the writer
  /// is asked once for the key.
  Future<GroupMessage> _open(GroupMessage m, {bool ask = false}) async {
    final sk = senderKeys;
    if (!GroupSenderKeys.isLocked(m.body)) return m;
    final opened =
        sk == null ? null : await sk.open(m.groupId, m.senderId, m.id, m.body);
    if (opened != null) return _withBody(m, opened);
    // Already open on this phone (it came Nearby too): keep that.
    final local = await store.groupMessageById(m.id);
    if (local != null && !GroupSenderKeys.isLocked(local.body)) {
      return _withBody(m, local.body);
    }
    if (ask) unawaited(_askKey(m.groupId, m.senderId, GroupSenderKeys.kidOf(m.body)));
    return m;
  }

  GroupMessage _withBody(GroupMessage m, String body) => GroupMessage(
        id: m.id,
        groupId: m.groupId,
        senderId: m.senderId,
        body: body,
        createdAt: m.createdAt,
        serverSeq: m.serverSeq,
        attachments: m.attachments,
        nearbySent: m.nearbySent,
      );

  Future<void> _askKey(String gid, String writer, String kid) async {
    final self = store.deviceId ?? '';
    if (kid.isEmpty || writer.isEmpty || writer == self) return;
    final k = '$gid|$writer|$kid';
    final last = _asked[k];
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(minutes: 10)) return;
    if (!socket.isConnected) return;
    _asked[k] = now;
    socket.send({
      'type': 'send_group_message',
      'id': _newId(),
      'group_id': gid,
      'body': GroupSenderKeys.askNote(writer, kid),
      'created_at': now.toUtc().toIso8601String(),
    }, durable: true);
    AppLogger.info('GROUP_SK_ASK');
  }

  /// Key notes and key asks (never chat lines). True = it was one.
  Future<bool> _consumeKeyNote(GroupMessage m) async {
    final sk = senderKeys;
    final self = store.deviceId ?? '';
    if (GroupSenderKeys.isKeys(m.body)) {
      if (sk == null || m.senderId == self) return true;
      final kid = await sk.acceptKeys(m.groupId, m.senderId, m.body);
      if (kid != null) {
        AppLogger.info('GROUP_SK_KEYS_GOT');
        unawaited(openLockedRows(gid: m.groupId, sender: m.senderId)
            .catchError((Object _) => 0));
      }
      return true;
    }
    final ask = GroupSenderKeys.parseAsk(m.body);
    if (ask == null) return GroupSenderKeys.isAsk(m.body);
    final (to, kid) = ask;
    if (sk == null || to != self || m.senderId == self) return true;
    final k = 'give|${m.groupId}|${m.senderId}|$kid';
    final last = _asked[k];
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return true;
    }
    _asked[k] = now;
    try {
      final members = await _otherMembers(m.groupId);
      if (!members.contains(m.senderId)) return true;
      final current = await sk.current(m.groupId, members);
      if (current.kid == kid) {
        // Send my current key again (a new note id = a new server line).
        await sk.markUndistributed(m.groupId);
        await _keyReady(m.groupId, <String>{});
      } else {
        // An older key (old messages): only to the one who asked.
        if (!await sk.ownKeyWasFor(m.groupId, kid, m.senderId)) return true;
        final old = await sk.ownKey(m.groupId, kid);
        if (old == null) return true;
        final note = await sk.keysNote(m.groupId, kid, old, [m.senderId]);
        if (note == null || !socket.isConnected) return true;
        socket.send({
          'type': 'send_group_message',
          'id': _newId(),
          'group_id': m.groupId,
          'body': note,
          'created_at': now.toUtc().toIso8601String(),
        }, durable: true);
      }
      AppLogger.info('GROUP_SK_KEY_RESENT');
    } catch (error) {
      AppLogger.warning('GROUP_SK_RESEND_FAILED', detail: '$error');
    }
    return true;
  }

  /// Opens rows saved locked (no key at the time, or saved by sync).
  /// Notes inside (reactions, pins, votes, deletes) are applied and their
  /// locked row removed; messages are saved open and shown.
  Future<int> openLockedRows({String? gid, String? sender}) async {
    final sk = senderKeys;
    if (sk == null) return 0;
    final ids = <String>[];
    if (gid != null) {
      ids.add(gid);
    } else {
      for (final row in await store.groups()) {
        ids.add(row['id']?.toString() ?? '');
      }
    }
    var opened = 0;
    for (final g in ids) {
      if (g.isEmpty) continue;
      final rows = (await store.groupMessages(g))
          .map(GroupMessage.fromJson)
          .where((m) =>
              GroupSenderKeys.isLocked(m.body) &&
              (sender == null || m.senderId == sender))
          .toList();
      for (final locked in rows) {
        final text = await sk.open(g, locked.senderId, locked.id, locked.body);
        if (text == null) continue;
        final m = _withBody(locked, text);
        opened++;
        if (await _consumeReaction(m) ||
            (await nearby?.consumeServerCard(m) ?? false)) {
          await store.deleteGroupMessageLocal(m.id);
          continue;
        }
        await store.saveGroupMessage(_messageMap(m));
        _incoming.add(m);
      }
    }
    if (opened > 0) AppLogger.info('GROUP_SK_REOPENED', detail: 'n=$opened');
    return opened;
  }

  // ------------------------------------------- Bundle G5b pin + polls

  void _bindExtrasHub() {
    final book = GroupExtrasBook.instance;
    book.read = store.readSetting;
    book.write = store.writeSetting;
    GroupExtrasHub.pin = pinMessage;
    GroupExtrasHub.unpin = unpin;
    GroupExtrasHub.sendPoll = sendPoll;
    GroupExtrasHub.vote = vote;
  }

  /// Owner or admin of [gid] (from this phone's member list).
  Future<bool> isGroupAdmin(String gid, String deviceId) async {
    if (gid.isEmpty || deviceId.isEmpty) return false;
    try {
      for (final row in await store.groupMembers(gid)) {
        if (row['device_id']?.toString() != deviceId) continue;
        final role = row['role']?.toString() ?? '';
        return role == 'owner' || role == 'admin';
      }
    } catch (_) {}
    return false;
  }

  /// P1/P2: pin [messageId] for [length] (admins only). One pin per group;
  /// a new pin replaces the old one.
  Future<bool> pinMessage(String gid, String messageId, Duration length) async {
    final self = store.deviceId ?? '';
    final group = await store.groupById(gid);
    if (group == null || !group.isActive || messageId.isEmpty) return false;
    if (!await isGroupAdmin(gid, self)) return false;
    final now = DateTime.now().toUtc();
    final note = GroupPinNote(
        messageId: messageId,
        at: now.toIso8601String(),
        until: now.add(length).toIso8601String(),
        by: self);
    final id = _newId();
    await GroupExtrasBook.instance.applyPin(gid, note);
    await _savePinLine(GroupMessage(
        id: id,
        groupId: gid,
        senderId: self,
        body: note.encode(),
        createdAt: note.at), note);
    await _queue({
      'id': id,
      'group_id': gid,
      'body': note.encode(),
      'created_at': note.at,
      'status': 'queued',
    });
    AppLogger.info('GROUP_PIN', detail: 'days=${length.inDays}');
    await flush();
    return true;
  }

  /// P4: take the pin away (admins only). No line in the chat.
  Future<bool> unpin(String gid) async {
    final self = store.deviceId ?? '';
    final group = await store.groupById(gid);
    if (group == null || !group.isActive) return false;
    if (!await isGroupAdmin(gid, self)) return false;
    final at = DateTime.now().toUtc().toIso8601String();
    final note = GroupPinNote(messageId: '', at: at, by: self);
    await GroupExtrasBook.instance.applyPin(gid, note);
    await _queue({
      'id': _newId(),
      'group_id': gid,
      'body': note.encode(),
      'created_at': at,
      'status': 'queued',
    });
    AppLogger.info('GROUP_UNPIN');
    await flush();
    return true;
  }

  /// Q2: a poll is a normal message (everyone who can send may make one).
  Future<bool> sendPoll(String gid, GroupPoll poll) async {
    await send(gid, poll.encode());
    AppLogger.info('GROUP_POLL_SENT',
        detail: 'options=${poll.options.length} multi=${poll.multi ? 'y' : 'n'}');
    return true;
  }

  /// Bundle 207 (K5): fast taps send only the last vote, this long after
  /// the last tap (tests: zero = at once).
  static Duration voteDelay = const Duration(milliseconds: 1500);
  final Map<String, Timer> _voteTimers = <String, Timer>{};
  final Map<String, ({String gid, GroupVote vote})> _voteWaiting =
      <String, ({String gid, GroupVote vote})>{};

  /// Q3: my picks on a poll (empty = take my vote back).
  /// Bundle 207 (K): one-answer polls can be changed for 3 minutes after my
  /// first vote; false = the vote is final (nothing goes out).
  Future<bool> vote(String gid, String pollId, List<int> choices) async {
    final self = store.deviceId ?? '';
    final group = await store.groupById(gid);
    if (self.isEmpty || group == null || !group.isActive || pollId.isEmpty) {
      return false;
    }
    var multi = false;
    try {
      final pm = await store.groupMessageById(pollId);
      multi = pm == null ? false : (GroupPoll.parse(pm.body)?.multi ?? false);
    } catch (_) {}
    final at = DateTime.now().toUtc().toIso8601String();
    var first = '';
    if (!multi) {
      final old = GroupExtrasBook.instance.voteOf(pollId, self);
      if (old != null && old.choices.isNotEmpty) {
        first = old.first.isNotEmpty ? old.first : old.at;
      } else if (choices.isNotEmpty) {
        first = at;
      }
      if (first.isNotEmpty && GroupVote.lateChange(first, at)) {
        AppLogger.info('GROUP_VOTE_FINAL');
        return false;
      }
    }
    final v = GroupVote(
        pollId: pollId,
        choices: List<int>.of(choices)..sort(),
        at: at,
        voter: self,
        // a take-back note carries no first time (a new vote starts again)
        first: choices.isEmpty ? '' : first);
    await GroupExtrasBook.instance.applyVote(v);
    AppLogger.info('GROUP_VOTE', detail: 'n=${choices.length}');
    if (voteDelay <= Duration.zero) {
      await _queueVote(gid, v);
      return true;
    }
    _voteWaiting[pollId] = (gid: gid, vote: v);
    _voteTimers.remove(pollId)?.cancel();
    _voteTimers[pollId] = Timer(voteDelay, () {
      _voteTimers.remove(pollId);
      final w = _voteWaiting.remove(pollId);
      if (w != null) unawaited(_queueVote(w.gid, w.vote));
    });
    return true;
  }

  Future<void> _queueVote(String gid, GroupVote v) async {
    await _queue({
      'id': _newId(),
      'group_id': gid,
      'body': v.encode(),
      'created_at': v.at,
      'status': 'queued',
    });
    AppLogger.info('GROUP_VOTE_SENT', detail: 'n=${v.choices.length}');
    await flush();
  }

  /// "Ali pinned a message" (a grey system line, never unread).
  Future<void> _savePinLine(GroupMessage note, GroupPinNote pin) async {
    final line = GroupMessage(
      id: note.id,
      groupId: note.groupId,
      senderId: note.senderId,
      body: GroupEvent(kind: 'pin', by: note.senderId, targets: [pin.messageId])
          .encode(),
      createdAt: note.createdAt,
      serverSeq: note.serverSeq,
    );
    final existed = (await store.groupMessageById(line.id)) != null;
    await store.saveGroupMessage(_messageMap(line));
    if (!existed) _incoming.add(line);
  }

  /// Pin / vote notes (socket, ack, history, Nearby). True = it was one
  /// (never shown as a bubble).
  Future<bool> _consumeExtra(GroupMessage message) async {
    final body = message.body;
    if (GroupPinNote.isPin(body)) {
      final note = GroupPinNote.parse(body, by: message.senderId);
      if (note == null) return true;
      if (!await isGroupAdmin(message.groupId, message.senderId)) {
        AppLogger.warning('GROUP_PIN_REFUSED', detail: 'reason=not_admin');
        return true;
      }
      try {
        await GroupExtrasBook.instance.applyPin(message.groupId, note);
        if (!note.isUnpin) await _savePinLine(message, note);
      } catch (_) {}
      return true;
    }
    if (GroupVote.isVote(body)) {
      final v = GroupVote.parse(body, voter: message.senderId);
      if (v != null && message.senderId.isNotEmpty) {
        try {
          await GroupExtrasBook.instance.applyVote(v);
        } catch (_) {}
      }
      return true;
    }
    return false;
  }

  Future<bool> _consumeReaction(GroupMessage message) async {
    // Bundle G5b: pin + vote notes.
    if (await _consumeExtra(message)) return true;
    // Bundle 197a: Delete for everyone (socket, ack, history).
    if (DeleteCommand.isDelete(message.body)) {
      try {
        await deletes.applyRemote(
            body: message.body, envelopeSender: message.senderId, group: true);
      } catch (_) {}
      return true;
    }
    if (!message.body.startsWith(_reactionPrefix)) return false;
    try {
      final payload = jsonDecode(message.body.substring(_reactionPrefix.length));
      if (payload is! Map) return true;
      final messageId = payload['message_id']?.toString() ?? '';
      final emoji = payload['emoji']?.toString() ?? '';
      final reactorId = payload['reactor_id']?.toString() ?? message.senderId;
      final createdAt = payload['created_at']?.toString() ?? message.createdAt;
      if (messageId.isEmpty || reactorId != message.senderId) return true;
      if (emoji.isEmpty) {
        // Bundle G1: the sender took the reaction back.
        await store.deleteGroupMessageReaction(messageId: messageId, reactorId: reactorId);
        _reactionIncoming.add(MessageReaction(messageId: messageId, reactorId: reactorId, emoji: '', createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now()));
        return true;
      }
      await store.saveGroupMessageReaction(messageId: messageId, reactorId: reactorId, emoji: emoji, createdAt: createdAt);
      _reactionIncoming.add(MessageReaction(messageId: messageId, reactorId: reactorId, emoji: emoji, createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now()));
    } catch (_) {}
    return true;
  }

  Future<void> _onMessage(Map<String, dynamic> data) async {
    final type = data['type']?.toString();
    if (type == 'error') {
      final id = data['id']?.toString();
      if (id == null || id.isEmpty) return;
      // Bundle G2: the server will never take it (removed / admins only):
      // stop retrying and take the bubble away.
      final code = data['error_code']?.toString() ?? '';
      if (code == 'GROUP_ADMINS_ONLY' || code == 'GROUP_NOT_MEMBER') {
        final outbox = (await store.groupOutbox())
            .where((row) => row['id']?.toString() == id)
            .toList();
        if (outbox.isEmpty) return;
        final groupId = outbox.first['group_id']?.toString() ?? '';
        // Bundle G3: a group with a card lives on phones too - the message
        // went Nearby; the server copy is just not possible.
        final cardGroup = await store.groupById(groupId);
        if (cardGroup != null && cardGroup.worksNearby) {
          await store.removeGroupOutbox(id);
          await store.removePendingGroupAttachments(id);
          AppLogger.warning('GROUP_SEND_REFUSED', detail: 'code=$code nearby=y');
          return;
        }
        await store.removeGroupOutbox(id);
        await store.removePendingGroupAttachments(id);
        try {
          await deletes.deleteForMe(id, group: true);
        } catch (_) {}
        AppLogger.warning('GROUP_SEND_REFUSED', detail: 'code=$code');
        if (code == 'GROUP_NOT_MEMBER' && groupId.isNotEmpty) {
          await store.setGroupState(groupId, 'removed');
          GroupChangeHub.instance.changed(groupId);
        }
        return;
      }
      await store.updateGroupOutboxStatus(id, 'queued');
      return;
    }
    if (type == 'group_message_ack') {
      final id = data['id']?.toString();
      if (id == null || id.isEmpty) return;
      final pending = await store.pendingGroupAttachments(id);
      final echoed = GroupMessage.fromJson(data);
      // Bundle G6: my key note / key ask reached the server.
      if (GroupSenderKeys.isKeys(echoed.body)) {
        await senderKeys?.markDistributed(echoed.groupId, id);
        return;
      }
      if (GroupSenderKeys.isAsk(echoed.body)) return;
      final base = await _open(echoed);
      final localRows = await store.groupMessages(base.groupId);
      final existing = localRows.map(GroupMessage.fromJson).where((m) => m.id == id).cast<GroupMessage?>().firstOrNull;
      if (existing == null && await _consumeReaction(base)) {
        await store.removeGroupOutbox(id);
        return;
      }
      // Bundle G3: my group card reached the server.
      if (base.body.startsWith(GroupNearbyService.cardBodyPrefix)) {
        await store.removeGroupOutbox(id);
        return;
      }
      final attachments = <Attachment>[];
      for (var i = 0; i < base.attachments.length; i++) {
        final localPath = i < pending.length ? pending[i]['local_path']?.toString() : null;
        attachments.add(base.attachments[i].copyWith(localPath: localPath));
        if (i < pending.length) {
          await MediaBook.instance.rename(pending[i]['id']?.toString() ?? '', base.attachments[i].id);
        }
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
      // Bundle G7: my own copies stay (shown in my bubble; Nearby sends to
      // members may still be running) - same as 1:1.
      _incoming.add(message);
      return;
    }
    // Bundle G5: a member got / read my message; someone is typing.
    if (type == 'group_receipt') {
      await recordReceipt(
          data['group_id']?.toString() ?? '',
          data['id']?.toString() ?? '',
          data['device_id']?.toString() ?? '',
          data['status']?.toString() == 'read' ? 'read' : 'delivered',
          at: data['created_at']?.toString() ?? '');
      return;
    }
    if (type == 'group_typing') {
      final sender = data['sender_id']?.toString() ?? '';
      if (sender.isEmpty || sender == (store.deviceId ?? '')) return;
      if (await store.isBlockedPeer(sender)) return;
      typingBook.note(data['group_id']?.toString() ?? '', sender,
          data['enabled'] != false);
      return;
    }
    // Bundle G6: someone asked to join with the invite link (admins only).
    if (type == 'group_join_request') {
      final gid = data['group_id']?.toString() ?? '';
      if (gid.isEmpty) return;
      AppLogger.info('GROUP_LINK_REQUEST', detail: 'gid=${gid.length > 6 ? gid.substring(0, 6) : gid}');
      try {
        await onJoinRequest?.call(gid);
      } catch (_) {}
      GroupChangeHub.instance.changed(gid);
      return;
    }
    if (type != 'group_message') return;
    try {
      var message = GroupMessage.fromJson(data);
      // Bundle G6: key notes; locked text opens here.
      if (await _consumeKeyNote(message)) return;
      message = await _open(message, ask: true);
      if (await _consumeReaction(message)) return;
      // Bundle G3: a group card through the server ('both' groups).
      if (await nearby?.consumeServerCard(message) ?? false) return;
      // Bundle G2: a system line ("Ali added you", "Sara left" ...).
      final event = GroupEvent.parse(message.body);
      if (event != null) {
        await applyEvent(message, event);
        return;
      }
      if (await store.isBlockedPeer(message.senderId)) return;
      final existed = (await store.groupMessages(message.groupId)).any((m) => m['id']?.toString() == message.id);
      await store.saveGroupMessage(_messageMap(message));
      typingBook.note(message.groupId, message.senderId, false);
      if (!existed) _incoming.add(message);
      // Bundle G5: tell the writer "got it".
      final self = store.deviceId ?? '';
      if (self.isNotEmpty && message.senderId != self &&
          _sendReceipt(message.groupId, [message.id], 'delivered')) {
        await store.putGroupReceipt(message.id, message.groupId, self,
            deliveredAt: DateTime.now().toUtc().toIso8601String());
      }
    } catch (_) {}
  }

  /// Bundle G2: one system line arrived (socket or history). Saves the
  /// line, updates my state (removed / left / added again) and reads the
  /// group info + members again.
  Future<void> applyEvent(GroupMessage message, GroupEvent event) async {
    final self = store.deviceId ?? '';
    final gid = message.groupId;
    if (gid.isEmpty) return;
    // Someone I blocked added me: leave quietly, nothing is shown.
    if (event.addsMe(self) &&
        event.by != self &&
        await store.isBlockedPeer(event.by)) {
      AppLogger.info('GROUP_ADD_BY_BLOCKED', detail: 'action=leave');
      try {
        await api.leaveGroup(gid);
      } catch (_) {}
      final paths = await store.deleteGroupLocal(gid);
      for (final path in paths) {
        await files.deleteLocalFile(path);
      }
      GroupChangeHub.instance.changed(gid);
      return;
    }
    var local = await store.groupById(gid);
    if (event.removesMe(self)) {
      if (local != null) await store.setGroupState(gid, 'removed');
    } else if (event.kind == 'leave' && event.by == self) {
      if (local != null) await store.setGroupState(gid, 'left');
    } else {
      if (event.addsMe(self) && local != null && !local.isActive) {
        await store.setGroupState(gid, 'active');
      }
      await refreshGroup(gid);
      local = await store.groupById(gid);
    }
    final existed = (await store.groupMessages(gid))
        .any((m) => m['id']?.toString() == message.id);
    await store.saveGroupMessage(_messageMap(message));
    AppLogger.info('GROUP_EVENT', detail: 'kind=${event.kind} new=${!existed}');
    if (!existed) _incoming.add(message);
    GroupChangeHub.instance.changed(gid);
  }

  /// Bundle G2: info + members from the server into this phone (the group
  /// row is made when it is new, e.g. "Ali added you").
  Future<void> refreshGroup(String gid) async {
    final local = await store.groupById(gid);
    // Bundle G3: a group only on phones: the card is the truth.
    if (local != null && local.nearbyOnly) return;
    try {
      final info = await api.groupInfo(gid);
      await store.saveGroup(info.toServerRow());
      // Bundle G3: a group with a card keeps the card's member list.
      if (local != null && local.worksNearby) {
        unawaited(GroupPhotoBook.instance
            .ensure(gid, info.photoVersion, () => api.groupPhoto(gid)));
        return;
      }
      final members = await api.groupMembers(gid);
      await store.replaceGroupMembers(gid, [
        for (final m in members)
          {
            'device_id': m.deviceId,
            'role': m.role,
            'joined_at': m.joinedAt,
            'name': m.name,
            'added_by': m.addedBy,
          }
      ]);
      unawaited(GroupPhotoBook.instance
          .ensure(gid, info.photoVersion, () => api.groupPhoto(gid)));
    } on GroupActionException catch (error) {
      if (error.code == 'GROUP_NOT_MEMBER' &&
          !(local != null && local.worksNearby)) {
        await store.setGroupState(gid, 'removed');
      }
    } catch (_) {
      // Offline: the next sync / home load fixes it.
    }
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    await nearby?.dispose();
    await _socketSub?.cancel();
    await _connectionSub?.cancel();
    await _reactionIncoming.close();
    await _incoming.close();
    await _typingTickSub?.cancel();
    typingBook.dispose();
    await _receiptChanges.close();
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
