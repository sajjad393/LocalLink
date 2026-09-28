import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:locallink/core/services/app_logger.dart';
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

  ReliableMessagingService(
      this.store,
      this.api,
      this.socket,
      this.files,
      this.connectivity,
      this.directTransport,
      this.crypto,
      this.groupCrypto,
      );

  Stream<Message> get incoming => _incoming.stream;

  void start() {
    AppLogger.info(
      'MESSAGE_SERVICE_START',
      detail:
      'device=${_shortId(store.deviceId)} '
          'serverConfigured=${store.serverAddress != null}',
    );

    _socketSub ??= socket.messages.listen(
      _handleSocketMessage,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(
          'MESSAGE_SOCKET_STREAM_ERROR',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );

    _directSub ??= directTransport.events.listen(
      _handleDirectEvent,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(
          'MESSAGE_DIRECT_STREAM_ERROR',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );

    _wifiSub ??= connectivity.wifiDirectEvents.listen(
          (_) {
        AppLogger.info(
          'MESSAGE_WIFI_DIRECT_EVENT',
        );

        unawaited(
          _configureDirectTransport(),
        );
      },
    );

    unawaited(
      _configureDirectTransport(),
    );

    _connectionSub ??= socket.connectionState.listen(
          (connected) async {
        AppLogger.info(
          'MESSAGE_SOCKET_STATE',
          detail: 'connected=$connected',
        );

        if (connected) {
          await synchronize();
          await flush();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(
          'MESSAGE_CONNECTION_STATE_ERROR',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );

    _retryTimer ??= Timer.periodic(
      const Duration(seconds: 5),
          (_) async {
        AppLogger.info(
          'MESSAGE_RETRY_TICK',
          detail:
          'socket=${socket.isConnected} '
              'direct=${directTransport.isStarted}',
        );

        if (socket.isConnected) {
          await synchronize();
        }

        await _configureDirectTransport();
        await flush();
      },
    );

    if (store.serverAddress != null) {
      AppLogger.info(
        'MESSAGE_INITIAL_SYNC',
      );

      unawaited(
        synchronize().then(
              (_) => flush(),
        ),
      );

      unawaited(
        api.connectRealtime().catchError(
              (Object error, StackTrace stackTrace) {
            AppLogger.error(
              'MESSAGE_REALTIME_CONNECT_FAILED',
              error: error,
              stackTrace: stackTrace,
            );
          },
        ),
      );
    }
  }

  Future<void> send(
      String recipientId,
      String body, {
        List<PickedFile> attachments = const [],
      }) async {
    AppLogger.info(
      'MESSAGE_SEND_START',
      detail:
      'recipient=${_shortId(recipientId)} '
          'bodyLength=${body.length} '
          'attachments=${attachments.length}',
    );

    if (await store.isBlockedPeer(recipientId)) {
      AppLogger.warning(
        'MESSAGE_SEND_BLOCKED_PEER',
        detail: 'recipient=${_shortId(recipientId)}',
      );

      throw Exception('This user is blocked');
    }

    final id = _newId();
    final now = DateTime.now().toUtc();

    if (body.isEmpty && attachments.isEmpty) {
      AppLogger.warning(
        'MESSAGE_SEND_EMPTY',
        detail: 'id=$id',
      );

      throw Exception('Message or attachment required');
    }

    if (body.length > 16 * 1024) {
      AppLogger.warning(
        'MESSAGE_SEND_TOO_LARGE',
        detail:
        'id=$id bodyLength=${body.length}',
      );

      throw Exception(
        'Message body must be 16KB or less',
      );
    }

    await store.addOutbox({
      'id': id,
      'recipient_id': recipientId,
      'body': body,
      'created_at': now.toIso8601String(),
      'status': 'queued',
    });

    AppLogger.info(
      'MESSAGE_OUTBOX_CREATED',
      detail:
      'id=$id '
          'recipient=${_shortId(recipientId)}',
    );

    final localAttachments = <Attachment>[];

    for (final file in attachments) {
      final fileId = _newId();

      await store.addPendingAttachment(
        id: fileId,
        messageId: id,
        file: file,
      );

      localAttachments.add(
        Attachment(
          id: fileId,
          originalName: file.name,
          contentType: file.contentType,
          size: file.size,
          sha256: '',
          isImage: file.contentType.startsWith('image/'),
          localPath: file.path,
        ),
      );

      AppLogger.info(
        'MESSAGE_ATTACHMENT_QUEUED',
        detail:
        'message=$id '
            'attachment=$fileId '
            'size=${file.size}',
      );
    }

    final message = Message(
      id: id,
      senderId: store.deviceId!,
      recipientId: recipientId,
      body: body,
      createdAt: now,
      status: 'queued',
      attachments: localAttachments,
    );

    await store.saveMessage(message);

    AppLogger.info(
      'MESSAGE_LOCAL_SAVED',
      detail:
      'id=$id '
          'sender=${_shortId(store.deviceId)} '
          'recipient=${_shortId(recipientId)}',
    );

    _incoming.add(message);

    AppLogger.info(
      'MESSAGE_LOCAL_EMITTED',
      detail: 'id=$id',
    );

    await flush();

    AppLogger.info(
      'MESSAGE_SEND_FLUSH_COMPLETE',
      detail: 'id=$id',
    );
  }

  Future<void> synchronize() async {
    if (_syncing) {
      AppLogger.info(
        'MESSAGE_SYNC_SKIPPED_ALREADY_RUNNING',
      );
      return;
    }

    if (store.deviceToken == null) {
      AppLogger.warning(
        'MESSAGE_SYNC_SKIPPED_NO_TOKEN',
      );
      return;
    }

    if (store.serverAddress == null) {
      AppLogger.warning(
        'MESSAGE_SYNC_SKIPPED_NO_SERVER',
      );
      return;
    }

    _syncing = true;

    AppLogger.info(
      'MESSAGE_SYNC_START',
      detail:
      'cursor=${store.syncCursor ?? '<none>'}',
    );

    try {
      await api.putIdentityKey(
        await crypto.publicKey(),
      );

      AppLogger.info(
        'MESSAGE_IDENTITY_KEY_SYNCED',
      );

      await refreshPeerKeys();

      var cursor = store.syncCursor;
      var hasMore = true;

      while (hasMore) {
        AppLogger.info(
          'MESSAGE_SYNC_PAGE_REQUEST',
          detail: 'cursor=${cursor ?? '<none>'}',
        );

        final page = await api.sync(
          cursor: cursor,
        );

        AppLogger.info(
          'MESSAGE_SYNC_PAGE_RECEIVED',
          detail:
          'messages=${page.messages.length} '
              'groups=${page.groups.length} '
              'groupMessages=${page.groupMessages.length} '
              'hasMore=${page.hasMore}',
        );

        for (final group in page.groups) {
          await store.saveGroup({
            'id': group.id,
            'name': group.name,
            'owner_id': group.ownerId,
            'created_at': group.createdAt,
          });
        }

        for (final member in page.groupMembers) {
          await store.saveGroupMember({
            'group_id': member.groupId,
            'device_id': member.deviceId,
            'role': member.role,
            'joined_at': member.joinedAt,
            'name': member.name,
          });
        }

        for (final groupId in page.removedGroupIds) {
          final localPaths =
          await store.deleteGroupLocal(groupId);

          for (final path in localPaths) {
            await files.deleteLocalFile(path);
          }
        }

        final groupKeySync = <String>{};

        for (final groupMessage in page.groupMessages) {
          if (groupKeySync.add(groupMessage.groupId)) {
            await groupCrypto.syncGroupKeys(
              groupMessage.groupId,
            );
          }

          final plaintext =
          await groupCrypto.decryptGroupMessage(
            groupMessage,
          );

          if (plaintext == null) {
            AppLogger.warning(
              'GROUP_MESSAGE_DECRYPT_FAILED',
              detail:
              'id=${groupMessage.id} '
                  'group=${_shortId(groupMessage.groupId)}',
            );
            continue;
          }

          await store.saveGroupMessage({
            'id': groupMessage.id,
            'group_id': groupMessage.groupId,
            'sender_id': groupMessage.senderId,
            'body': plaintext,
            'created_at': groupMessage.createdAt,
            'server_seq': groupMessage.serverSeq,
            'attachments':
            groupMessage.attachments
                .map((a) => a.toJson())
                .toList(),
          });
        }

        for (final networkMessage in page.messages) {
          AppLogger.info(
            'MESSAGE_SYNC_NETWORK_MESSAGE',
            detail:
            'id=${networkMessage.id} '
                'sender=${_shortId(networkMessage.senderId)} '
                'recipient=${_shortId(networkMessage.recipientId)} '
                'status=${networkMessage.status}',
          );

          final message =
          await _decryptMessageModel(networkMessage);

          if (message == null) {
            AppLogger.warning(
              'MESSAGE_SYNC_MESSAGE_DROPPED',
              detail:
              'id=${networkMessage.id} '
                  'sender=${_shortId(networkMessage.senderId)}',
            );
            continue;
          }

          if (await store.isBlockedPeer(message.senderId)) {
            AppLogger.warning(
              'MESSAGE_SYNC_BLOCKED_MESSAGE',
              detail:
              'id=${message.id} '
                  'sender=${_shortId(message.senderId)}',
            );
            continue;
          }

          final existed =
          await store.messageExists(message.id);

          await store.saveMessage(message);

          AppLogger.info(
            'MESSAGE_SYNC_SAVED',
            detail:
            'id=${message.id} '
                'existed=$existed',
          );

          if (!existed &&
              message.recipientId == store.deviceId &&
              message.senderId != store.deviceId) {
            _incoming.add(message);

            AppLogger.info(
              'MESSAGE_SYNC_INCOMING_EMITTED',
              detail: 'id=${message.id}',
            );
          }

          if (message.recipientId == store.deviceId &&
              message.status != 'delivered') {
            try {
              final delivered =
              await api.acknowledgeMessage(
                message.id,
              );

              await store.updateMessageStatus(
                delivered.id,
                status: delivered.status,
                deliveredAt: delivered.deliveredAt,
              );

              AppLogger.info(
                'MESSAGE_DELIVERY_ACK_SUCCESS',
                detail:
                'id=${message.id} '
                    'status=${delivered.status}',
              );
            } catch (error, stackTrace) {
              AppLogger.error(
                'MESSAGE_DELIVERY_ACK_FAILED',
                error: error,
                stackTrace: stackTrace,
                detail: 'id=${message.id}',
              );
            }
          }

          if (message.senderId == store.deviceId) {
            if (message.status == 'delivered') {
              await store.updateOutboxStatus(
                message.id,
                'delivered',
              );

              await store.removeOutbox(
                message.id,
              );

              AppLogger.info(
                'MESSAGE_OUTBOX_DELIVERED_FROM_SYNC',
                detail: 'id=${message.id}',
              );
            } else {
              await store.updateOutboxStatus(
                message.id,
                'sent',
              );
            }
          }
        }

        final next = page.nextCursor;

        if (next != null &&
            next.isNotEmpty) {
          await store.saveSyncCursor(next);
          cursor = next;

          AppLogger.info(
            'MESSAGE_SYNC_CURSOR_UPDATED',
            detail: 'cursorUpdated=true',
          );
        }

        hasMore = page.hasMore;

        if (page.hasMore &&
            (next == null || next.isEmpty)) {
          AppLogger.warning(
            'MESSAGE_SYNC_INVALID_CURSOR',
          );
          break;
        }
      }

      AppLogger.info(
        'MESSAGE_SYNC_SUCCESS',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'MESSAGE_SYNC_FAILED',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _syncing = false;

      AppLogger.info(
        'MESSAGE_SYNC_FINISH',
      );
    }
  }

  Future<void> flush() async {
    if (_flushing) {
      AppLogger.info(
        'MESSAGE_FLUSH_SKIPPED_ALREADY_RUNNING',
      );
      return;
    }

    if (!socket.isConnected && !directTransport.isStarted) {
      AppLogger.info(
        'MESSAGE_FLUSH_SKIPPED_NO_TRANSPORT',
      );
      return;
    }

    _flushing = true;

    AppLogger.info(
      'MESSAGE_FLUSH_START',
      detail:
      'socket=${socket.isConnected} '
          'direct=${directTransport.isStarted}',
    );

    try {
      final items = await store.outbox();

      AppLogger.info(
        'MESSAGE_OUTBOX_READ',
        detail: 'count=${items.length}',
      );

      for (final item in items) {
        final id = item['id'].toString();

        final status = item['status']?.toString() ?? 'queued';

        AppLogger.info(
          'MESSAGE_FLUSH_ITEM',
          detail:
          'id=$id '
              'status=$status',
        );

        if (status == 'delivered') {
          await store.removeOutbox(id);

          AppLogger.info(
            'MESSAGE_OUTBOX_CLEANED',
            detail: 'id=$id',
          );

          continue;
        }

        if (status == 'direct_delivered' && !socket.isConnected) {
          continue;
        }

        final recipientId = item['recipient_id'].toString();

        final pending = await store.pendingAttachments(id);

        final canUseDirect =
            !socket.isConnected && directTransport.isStarted;

        // ------------------------------------------------------------------
        // DIRECT / WI-FI TRANSPORT
        // ------------------------------------------------------------------
        if (canUseDirect) {
          AppLogger.info(
            'MESSAGE_DIRECT_TRANSPORT_SELECTED',
            detail:
            'id=$id '
                'recipient=${_shortId(recipientId)}',
          );

          try {
            final attachments = <Map<String, dynamic>>[];

            for (final attachment in pending) {
              final file = PickedFile(
                path: attachment['local_path'].toString(),
                name: attachment['original_name'].toString(),
                contentType: attachment['content_type'].toString(),
                size:
                int.tryParse(
                  attachment['size'].toString(),
                ) ??
                    0,
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

            final derived = await crypto.derivePeerKeys(
              publicKeys,
            );

            final shared = derived[recipientId];

            if (shared == null) {
              AppLogger.error(
                'MESSAGE_DIRECT_ENCRYPTION_KEY_MISSING',
                detail:
                'id=$id '
                    'recipient=${_shortId(recipientId)}',
              );

              throw StateError(
                'peer encryption key unavailable',
              );
            }

            var encryptedBody =
            await store.outboxNetworkBody(id);

            encryptedBody ??= await crypto.encryptMessage(
              senderId: store.deviceId!,
              recipientId: recipientId,
              messageId: id,
              createdAt: item['created_at']?.toString() ?? '',
              plaintext: item['body']?.toString() ?? '',
              sharedKey: shared,
            );

            await store.setOutboxNetworkBody(
              id,
              encryptedBody,
            );

            // IMPORTANT:
            // directTransport.send() currently returns void.
            // Therefore DO NOT do:
            //
            // final sent = await directTransport.send(...);
            //
            // because `sent` would have type void.
            await directTransport.send(
              recipientId: recipientId,
              payload: {
                'type': 'direct_message',
                'id': id,
                'sender_id': store.deviceId,
                'recipient_id': recipientId,
                'body': encryptedBody,
                'created_at': item['created_at'],
                if (attachments.isNotEmpty)
                  'attachments': attachments,
              },
            );

            AppLogger.info(
              'MESSAGE_DIRECT_SEND_ACCEPTED',
              detail:
              'id=$id '
                  'recipient=${_shortId(recipientId)}',
            );

            await store.updateOutboxStatus(
              id,
              'sending',
            );

            await store.markOutboxAttempt(id);
          } catch (error, stackTrace) {
            AppLogger.error(
              'MESSAGE_DIRECT_SEND_FAILED',
              error: error,
              stackTrace: stackTrace,
              detail: 'id=$id',
            );
          }

          continue;
        }

        // ------------------------------------------------------------------
        // SERVER / WEBSOCKET TRANSPORT
        // ------------------------------------------------------------------
        if (!socket.isConnected) {
          AppLogger.warning(
            'MESSAGE_SOCKET_SEND_SKIPPED_NOT_CONNECTED',
            detail: 'id=$id',
          );

          continue;
        }

        AppLogger.info(
          'MESSAGE_SERVER_TRANSPORT_SELECTED',
          detail:
          'id=$id '
              'recipient=${_shortId(recipientId)}',
        );

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
              size:
              int.tryParse(
                attachment['size'].toString(),
              ) ??
                  0,
            );

            final uploaded = await files.uploadE2eForMessage(
              picked,
              recipientId: recipientId,
              messageId: id,
              createdAt: item['created_at']?.toString() ?? '',
              clientFileId: attachment['id']?.toString() ?? '',
              operationId: id,
            );

            await store.setPendingRemoteFile(
              attachment['id'].toString(),
              uploaded.id,
            );

            remoteIds.add(uploaded.id);

            AppLogger.info(
              'MESSAGE_ATTACHMENT_UPLOADED',
              detail:
              'message=$id '
                  'attachment=${attachment['id']}',
            );
          } catch (error, stackTrace) {
            uploadFailed = true;

            AppLogger.error(
              'MESSAGE_ATTACHMENT_UPLOAD_FAILED',
              error: error,
              stackTrace: stackTrace,
              detail:
              'message=$id '
                  'attachment=${attachment['id']}',
            );

            break;
          }
        }

        if (uploadFailed) {
          continue;
        }

        final publicKeys = await crypto.cachedPeerPublicKeys();

        final derived = await crypto.derivePeerKeys(
          publicKeys,
        );

        final shared = derived[recipientId];

        if (shared == null) {
          AppLogger.error(
            'MESSAGE_SERVER_ENCRYPTION_KEY_MISSING',
            detail:
            'id=$id '
                'recipient=${_shortId(recipientId)}',
          );

          continue;
        }

        var encryptedBody =
        await store.outboxNetworkBody(id);

        encryptedBody ??= await crypto.encryptMessage(
          senderId: store.deviceId!,
          recipientId: recipientId,
          messageId: id,
          createdAt: item['created_at']?.toString() ?? '',
          plaintext: item['body']?.toString() ?? '',
          sharedKey: shared,
        );

        await store.setOutboxNetworkBody(
          id,
          encryptedBody,
        );

        // socket.send() DOES return bool, so this is valid.
        final sent = socket.send(
          {
            'type': 'send_message',
            'id': id,
            'recipient_id': recipientId,
            'body': encryptedBody,
            if (remoteIds.isNotEmpty)
              'attachment_ids': remoteIds,
          },
          durable: true,
        );

        AppLogger.info(
          'MESSAGE_SERVER_SEND_RESULT',
          detail:
          'id=$id '
              'sent=$sent '
              'recipient=${_shortId(recipientId)}',
        );

        if (!sent) {
          AppLogger.warning(
            'MESSAGE_SERVER_SEND_NOT_ACCEPTED',
            detail: 'id=$id',
          );
        }

        await store.markOutboxAttempt(id);
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'MESSAGE_FLUSH_FAILED',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _flushing = false;

      AppLogger.info(
        'MESSAGE_FLUSH_FINISH',
      );
    }
  }

  Future<Message?> _decryptMessageModel(
      Message message,
      ) async {
    AppLogger.info(
      'MESSAGE_DECRYPT_START',
      detail:
      'id=${message.id} '
          'sender=${_shortId(message.senderId)} '
          'recipient=${_shortId(message.recipientId)}',
    );

    if (message.senderId == store.deviceId) {
      final local =
      await store.messageById(message.id);

      if (local != null) {
        AppLogger.info(
          'MESSAGE_DECRYPT_SELF_SUCCESS',
          detail: 'id=${message.id}',
        );

        return Message(
          id: local.id,
          senderId: local.senderId,
          recipientId: local.recipientId,
          body: local.body,
          createdAt: local.createdAt,
          status: message.status,
          deliveredAt:
          message.deliveredAt ??
              local.deliveredAt,
          serverSeq:
          message.serverSeq >
              local.serverSeq
              ? message.serverSeq
              : local.serverSeq,
          attachments:
          message.attachments.isNotEmpty
              ? message.attachments
              : local.attachments,
        );
      }

      AppLogger.warning(
        'MESSAGE_SELF_LOCAL_COPY_MISSING',
        detail: 'id=${message.id}',
      );

      return null;
    }

    final peerPublic =
    (await crypto.cachedPeerPublicKeys())[
    message.senderId];

    if (peerPublic == null) {
      AppLogger.error(
        'MESSAGE_DECRYPT_PEER_KEY_MISSING',
        detail:
        'id=${message.id} '
            'sender=${_shortId(message.senderId)}',
      );

      return null;
    }

    final shared =
    await crypto.deriveSharedKey(
      message.senderId,
      peerPublic,
    );

    var body =
    await crypto.decryptMessage(
      senderId: message.senderId,
      recipientId: message.recipientId,
      messageId: message.id,
      createdAt:
      message.createdAt
          .toUtc()
          .toIso8601String(),
      value: message.body,
      sharedKey: shared,
    );

    if (body != null) {
      AppLogger.info(
        'MESSAGE_DECRYPT_SUCCESS',
        detail: 'id=${message.id} method=primary',
      );
    }

    if (body == null &&
        message.body.startsWith('e2e:v2:')) {
      AppLogger.warning(
        'MESSAGE_DECRYPT_PRIMARY_FAILED',
        detail:
        'id=${message.id} trying=identity_history',
      );

      final history =
      await crypto.cachedPeerIdentityHistory();

      final candidates =
          history[message.senderId] ??
              {1: peerPublic};

      body =
      await crypto.decryptMessageWithHistory(
        senderId: message.senderId,
        recipientId: message.recipientId,
        messageId: message.id,
        createdAt:
        message.createdAt
            .toUtc()
            .toIso8601String(),
        value: message.body,
        peerKeysByVersion: candidates,
      );

      if (body != null) {
        AppLogger.info(
          'MESSAGE_DECRYPT_SUCCESS',
          detail:
          'id=${message.id} '
              'method=identity_history',
        );
      }
    }

    if (body == null &&
        message.body.startsWith('e2e:v2:')) {
      AppLogger.warning(
        'MESSAGE_DECRYPT_HISTORY_FAILED',
        detail:
        'id=${message.id} '
            'trying=identity_contexts',
      );

      final publicKeys =
      await crypto.cachedPeerPublicKeys();

      final history =
      await crypto.cachedPeerIdentityHistory();

      final senderCandidates =
      <int, String>{};

      senderCandidates.addAll(
        history[message.senderId] ??
            const {},
      );

      if (publicKeys[message.senderId] != null) {
        senderCandidates[1] =
        publicKeys[message.senderId]!;
      }

      final recipientCandidates =
      <int, String>{};

      recipientCandidates.addAll(
        history[message.recipientId] ??
            const {},
      );

      if (publicKeys[message.recipientId] != null) {
        recipientCandidates[1] =
        publicKeys[message.recipientId]!;
      }

      final importedSelfIsSender =
      (await crypto
          .importedIdentityKeyContexts())
          .containsKey(message.senderId);

      final importedCandidates =
      importedSelfIsSender
          ? recipientCandidates
          : senderCandidates;

      body =
      await crypto
          .decryptMessageWithIdentityContexts(
        senderId: message.senderId,
        recipientId: message.recipientId,
        messageId: message.id,
        createdAt:
        message.createdAt
            .toUtc()
            .toIso8601String(),
        value: message.body,
        peerKeysByVersion:
        importedCandidates,
      );

      if (body != null) {
        AppLogger.info(
          'MESSAGE_DECRYPT_SUCCESS',
          detail:
          'id=${message.id} '
              'method=identity_contexts',
        );
      }
    }

    if (body == null) {
      if (!message.body.startsWith('e2e:v1:')) {
        AppLogger.warning(
          'MESSAGE_DECRYPT_PLAINTEXT_FALLBACK',
          detail: 'id=${message.id}',
        );

        return message;
      }

      AppLogger.error(
        'MESSAGE_DECRYPT_FAILED',
        detail:
        'id=${message.id} '
            'reason=all_decryption_methods_failed',
      );

      return null;
    }

    return Message(
      id: message.id,
      senderId: message.senderId,
      recipientId: message.recipientId,
      body: body,
      createdAt: message.createdAt,
      status: message.status,
      deliveredAt: message.deliveredAt,
      serverSeq: message.serverSeq,
      attachments: message.attachments,
    );
  }

  Future<Message?> _decryptNetworkMessage(
      Map<String, dynamic> data,
      ) async {
    final id = data['id']?.toString() ?? '';

    AppLogger.info(
      'NETWORK_MESSAGE_DECRYPT_START',
      detail:
      'id=$id '
          'type=${data['type']?.toString() ?? 'unknown'} '
          'sender=${_shortId(data['sender_id']?.toString())}',
    );

    try {
      final message =
      Message.fromJson(data);

      AppLogger.info(
        'NETWORK_MESSAGE_PARSED',
        detail:
        'id=${message.id} '
            'sender=${_shortId(message.senderId)} '
            'recipient=${_shortId(message.recipientId)}',
      );

      if (message.senderId == store.deviceId) {
        final local =
        await store.messageById(message.id);

        if (local == null) {
          AppLogger.warning(
            'NETWORK_SELF_MESSAGE_LOCAL_COPY_MISSING',
            detail: 'id=${message.id}',
          );

          return null;
        }

        AppLogger.info(
          'NETWORK_SELF_MESSAGE_RESOLVED',
          detail: 'id=${message.id}',
        );

        return Message(
          id: local.id,
          senderId: local.senderId,
          recipientId: local.recipientId,
          body: local.body,
          createdAt: local.createdAt,
          status: message.status,
          deliveredAt:
          message.deliveredAt ??
              local.deliveredAt,
          serverSeq:
          message.serverSeq >
              local.serverSeq
              ? message.serverSeq
              : local.serverSeq,
          attachments:
          message.attachments.isNotEmpty
              ? message.attachments
              : local.attachments,
        );
      }

      final peerPublic =
      (await crypto.cachedPeerPublicKeys())[
      message.senderId];

      if (peerPublic == null) {
        AppLogger.error(
          'NETWORK_MESSAGE_PEER_KEY_MISSING',
          detail:
          'id=${message.id} '
              'sender=${_shortId(message.senderId)}',
        );

        return null;
      }

      final key =
      await crypto.deriveSharedKey(
        message.senderId,
        peerPublic,
      );

      var body =
      await crypto.decryptMessage(
        senderId: message.senderId,
        recipientId: store.deviceId!,
        messageId: message.id,
        createdAt:
        message.createdAt
            .toUtc()
            .toIso8601String(),
        value: message.body,
        sharedKey: key,
      );

      if (body != null) {
        AppLogger.info(
          'NETWORK_MESSAGE_DECRYPT_SUCCESS',
          detail:
          'id=${message.id} '
              'method=primary',
        );
      }

      if (body == null &&
          message.body.startsWith('e2e:v2:')) {
        AppLogger.warning(
          'NETWORK_MESSAGE_PRIMARY_DECRYPT_FAILED',
          detail:
          'id=${message.id} '
              'trying=history',
        );

        final history =
        await crypto.cachedPeerIdentityHistory();

        final candidates =
            history[message.senderId] ??
                {1: peerPublic};

        body =
        await crypto.decryptMessageWithHistory(
          senderId: message.senderId,
          recipientId: store.deviceId!,
          messageId: message.id,
          createdAt:
          message.createdAt
              .toUtc()
              .toIso8601String(),
          value: message.body,
          peerKeysByVersion: candidates,
        );

        if (body != null) {
          AppLogger.info(
            'NETWORK_MESSAGE_DECRYPT_SUCCESS',
            detail:
            'id=${message.id} '
                'method=history',
          );
        }
      }

      if (body == null &&
          message.body.startsWith('e2e:v2:')) {
        AppLogger.warning(
          'NETWORK_MESSAGE_HISTORY_DECRYPT_FAILED',
          detail:
          'id=${message.id} '
              'trying=identity_contexts',
        );

        final publicKeys =
        await crypto.cachedPeerPublicKeys();

        final history =
        await crypto.cachedPeerIdentityHistory();

        final candidates =
        <int, String>{};

        candidates.addAll(
          history[message.senderId] ??
              const {},
        );

        if (publicKeys[message.senderId] !=
            null) {
          candidates[1] =
          publicKeys[message.senderId]!;
        }

        body =
        await crypto
            .decryptMessageWithIdentityContexts(
          senderId: message.senderId,
          recipientId: store.deviceId!,
          messageId: message.id,
          createdAt:
          message.createdAt
              .toUtc()
              .toIso8601String(),
          value: message.body,
          peerKeysByVersion: candidates,
        );

        if (body != null) {
          AppLogger.info(
            'NETWORK_MESSAGE_DECRYPT_SUCCESS',
            detail:
            'id=${message.id} '
                'method=identity_contexts',
          );
        }
      }

      if (body == null) {
        AppLogger.error(
          'NETWORK_MESSAGE_DECRYPT_FAILED',
          detail:
          'id=${message.id} '
              'reason=all_methods_failed',
        );

        return null;
      }

      AppLogger.info(
        'NETWORK_MESSAGE_READY',
        detail:
        'id=${message.id} '
            'recipient=${_shortId(message.recipientId)}',
      );

      return Message(
        id: message.id,
        senderId: message.senderId,
        recipientId: message.recipientId,
        body: body,
        createdAt: message.createdAt,
        status: message.status,
        deliveredAt: message.deliveredAt,
        serverSeq: message.serverSeq,
        attachments: message.attachments,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'NETWORK_MESSAGE_DECRYPT_EXCEPTION',
        error: error,
        stackTrace: stackTrace,
        detail: 'id=$id',
      );

      return null;
    }
  }

  Future<void> _handleSocketMessage(
      Map<String, dynamic> data,
      ) async {
    final type =
    data['type']?.toString();

    final id =
    data['id']?.toString();

    AppLogger.info(
      'MESSAGE_SOCKET_EVENT',
      detail:
      'type=${type ?? 'unknown'} '
          'id=${id ?? ''} '
          'sender=${_shortId(data['sender_id']?.toString())} '
          'recipient=${_shortId(data['recipient_id']?.toString())}',
    );

    if (type == 'error') {
      if (id != null && id.isNotEmpty) {
        await store.updateOutboxStatus(
          id,
          'queued',
        );

        AppLogger.warning(
          'MESSAGE_SERVER_ERROR_EVENT',
          detail: 'id=$id',
        );
      }

      return;
    }

    if (type == 'message_ack') {
      if (id == null || id.isEmpty) {
        AppLogger.warning(
          'MESSAGE_ACK_MISSING_ID',
        );

        return;
      }

      AppLogger.info(
        'MESSAGE_ACK_RECEIVED',
        detail: 'id=$id',
      );

      final pending =
      await store.pendingAttachments(id);

      final localPaths = pending
          .map(
            (row) =>
            row['local_path']
                ?.toString(),
      )
          .whereType<String>()
          .where(
            (path) => path.isNotEmpty,
      )
          .toList();

      final existed =
      await store.messageExists(id);

      final base =
      await _decryptNetworkMessage(data);

      if (base == null) {
        AppLogger.error(
          'MESSAGE_ACK_DECRYPT_FAILED',
          detail: 'id=$id',
        );

        return;
      }

      final atts = <Attachment>[];

      for (final attachment
      in base.attachments) {
        atts.add(attachment);
      }

      final message = Message(
        id: base.id,
        senderId: base.senderId,
        recipientId: base.recipientId,
        body: base.body,
        createdAt: base.createdAt,
        status: base.status,
        deliveredAt: base.deliveredAt,
        serverSeq: base.serverSeq,
        attachments: atts,
      );

      await store.updateOutboxStatus(
        id,
        data['status']?.toString() ??
            'sent',
      );

      await store.saveMessage(
        message,
      );

      await store.removePendingAttachments(
        id,
      );

      for (final path in localPaths) {
        await files.deleteLocalFile(path);
      }

      if (!existed) {
        _incoming.add(message);

        AppLogger.info(
          'MESSAGE_ACK_INCOMING_EMITTED',
          detail: 'id=$id',
        );
      }

      AppLogger.info(
        'MESSAGE_ACK_PROCESSED',
        detail:
        'id=$id '
            'status=${message.status}',
      );

      return;
    }

    if (type == 'delivery_ack') {
      if (id == null || id.isEmpty) {
        AppLogger.warning(
          'MESSAGE_DELIVERY_ACK_MISSING_ID',
        );

        return;
      }

      final status =
          data['status']?.toString() ??
              'delivered';

      await store.updateOutboxStatus(
        id,
        status,
      );

      await store.updateMessageStatus(
        id,
        status: status,
        deliveredAt:
        data['created_at']
            ?.toString(),
      );

      AppLogger.info(
        'MESSAGE_DELIVERY_ACK_PROCESSED',
        detail:
        'id=$id '
            'status=$status',
      );

      if (status == 'delivered' ||
          status == 'direct_delivered') {
        await store.removeOutbox(id);

        AppLogger.info(
          'MESSAGE_OUTBOX_REMOVED_AFTER_DELIVERY',
          detail: 'id=$id',
        );
      }

      return;
    }

    if (type != 'message') {
      AppLogger.info(
        'MESSAGE_SOCKET_EVENT_IGNORED',
        detail:
        'type=${type ?? 'unknown'}',
      );

      return;
    }

    try {
      AppLogger.info(
        'MESSAGE_INCOMING_FROM_SERVER',
        detail: 'id=${id ?? ''}',
      );

      final message =
      await _decryptNetworkMessage(data);

      if (message == null) {
        AppLogger.error(
          'MESSAGE_INCOMING_DROPPED_AFTER_DECRYPT',
          detail: 'id=${id ?? ''}',
        );

        return;
      }

      if (await store.isBlockedPeer(
        message.senderId,
      )) {
        AppLogger.warning(
          'MESSAGE_INCOMING_BLOCKED_PEER',
          detail:
          'id=${message.id} '
              'sender=${_shortId(message.senderId)}',
        );

        return;
      }

      final existed =
      await store.messageExists(
        message.id,
      );

      await store.saveMessage(
        message,
      );

      AppLogger.info(
        'MESSAGE_INCOMING_SAVED',
        detail:
        'id=${message.id} '
            'existed=$existed',
      );

      final ackSent = socket.send(
        {
          'type': 'ack_delivery',
          'id': message.id,
        },
      );

      AppLogger.info(
        'MESSAGE_DELIVERY_ACK_SENT',
        detail:
        'id=${message.id} '
            'sent=$ackSent',
      );

      if (!existed) {
        _incoming.add(message);

        AppLogger.info(
          'MESSAGE_INCOMING_EMITTED',
          detail:
          'id=${message.id}',
        );
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'MESSAGE_SOCKET_PROCESSING_FAILED',
        error: error,
        stackTrace: stackTrace,
        detail: 'id=${id ?? ''}',
      );
    }
  }

  Future<void> _configureDirectTransport() async {
    if (store.deviceId == null) {
      AppLogger.warning(
        'DIRECT_TRANSPORT_CONFIG_SKIPPED_NO_DEVICE',
      );

      return;
    }

    try {
      final info =
      await connectivity
          .wifiDirectConnectionInfo();

      AppLogger.info(
        'DIRECT_TRANSPORT_INFO',
        detail:
        'connected=${info.connected} '
            'groupOwner=${info.groupOwner}',
      );

      final publicKeys =
      await crypto.cachedPeerPublicKeys();

      final keys =
      await crypto.derivePeerKeys(
        publicKeys,
      );

      await directTransport.configure(
        deviceId: store.deviceId!,
        connected: info.connected,
        groupOwner: info.groupOwner,
        groupOwnerAddress:
        info.groupOwnerAddress,
        peerKeys: keys,
      );

      AppLogger.info(
        'DIRECT_TRANSPORT_CONFIGURED',
        detail:
        'connected=${info.connected} '
            'keys=${keys.length}',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'DIRECT_TRANSPORT_CONFIG_FAILED',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> refreshPeerKeys() async {
    if (store.deviceToken == null ||
        store.serverAddress == null) {
      AppLogger.warning(
        'PEER_KEYS_REFRESH_SKIPPED',
      );

      return;
    }

    try {
      AppLogger.info(
        'PEER_KEYS_REFRESH_START',
      );

      final records =
      await api.identityKeyRecords();

      final publicKeys = {
        for (final record in records)
          record.peerId: record.publicKey,
      };

      final versions = {
        for (final record in records)
          record.peerId: record.keyVersion,
      };

      final changedPeers =
      await crypto.cachePeerPublicKeys(
        publicKeys,
        versions: versions,
      );

      _blockedIdentityPeers.addAll(
        changedPeers,
      );

      try {
        await crypto.cachePeerIdentityHistory(
          await api.allIdentityKeyHistory(),
        );
      } catch (error, stackTrace) {
        AppLogger.error(
          'PEER_KEY_HISTORY_REFRESH_FAILED',
          error: error,
          stackTrace: stackTrace,
        );
      }

      final cached =
      await crypto.cachedPeerPublicKeys();

      cached.removeWhere(
            (id, _) =>
            _blockedIdentityPeers.contains(id),
      );

      final keys =
      await crypto.derivePeerKeys(
        cached,
      );

      await directTransport.updatePeerKeys(
        keys,
      );

      AppLogger.info(
        'PEER_KEYS_REFRESH_SUCCESS',
        detail:
        'peers=${publicKeys.length} '
            'derived=${keys.length} '
            'changed=${changedPeers.length}',
      );

      if (changedPeers.isNotEmpty) {
        throw StateError(
          'peer identity changed without a newer key version: '
              '${changedPeers.join(',')}',
        );
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'PEER_KEYS_REFRESH_FAILED',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _handleDirectEvent(
      Map<String, dynamic> event,
      ) async {
    final eventType = event['type']?.toString();

    AppLogger.info(
      'DIRECT_EVENT_RECEIVED',
      detail:
      'type=${eventType ?? 'unknown'} '
          'message=${event['message_id']?.toString() ?? ''}',
    );

    // ------------------------------------------------------------------------
    // DIRECT FILE RECEIVED
    // ------------------------------------------------------------------------
    if (eventType == 'file_received') {
      final fileId = event['file_id']?.toString();
      final messageId = event['message_id']?.toString();
      final path = event['path']?.toString();
      final senderId = event['sender_id']?.toString();

      if ([
        fileId,
        messageId,
        path,
        senderId,
      ].any(
            (v) => v == null || v!.isEmpty,
      )) {
        AppLogger.warning(
          'DIRECT_FILE_EVENT_INVALID',
        );

        return;
      }

      if (await store.isBlockedPeer(senderId!)) {
        AppLogger.warning(
          'DIRECT_FILE_BLOCKED_PEER',
          detail:
          'sender=${_shortId(senderId)}',
        );

        return;
      }

      final meta = <String, dynamic>{
        'file_id': fileId,
        'message_id': messageId,
        'path': path,
        'sender_id': senderId,
        'original_name':
        event['file_name']?.toString() ??
            'attachment',
        'content_type':
        event['content_type']?.toString() ??
            'application/octet-stream',
        'size':
        int.tryParse(
          event['size']?.toString() ?? '',
        ) ??
            0,
        'sha256':
        event['sha256']?.toString() ??
            '',
      };

      final protectedPath =
      await files.protectLegacyLocalFile(path!);

      _recentDirectFiles[fileId!] = {
        ...meta,
        'path': protectedPath,
      };

      await store.saveDirectFile(
        fileId: fileId,
        messageId: messageId!,
        senderId: senderId,
        localPath: protectedPath,
        originalName:
        meta['original_name'] as String,
        contentType:
        meta['content_type'] as String,
        size: meta['size'] as int,
        sha256: meta['sha256'] as String,
      );

      final messages =
      await store.messagesFor(senderId);

      for (final message in messages.where(
            (m) => m.id == messageId,
      )) {
        final updated =
        message.copyWithMessageAttachments(
          await _attachmentsWithDirectFiles(
            message.attachments,
          ),
        );

        await store.saveMessage(updated);

        _incoming.add(updated);

        AppLogger.info(
          'DIRECT_FILE_MESSAGE_UPDATED',
          detail:
          'message=$messageId '
              'file=$fileId',
        );
      }

      return;
    }

    // ------------------------------------------------------------------------
    // ONLY PROCESS DIRECT MESSAGE EVENTS
    // ------------------------------------------------------------------------
    if (eventType != 'message') {
      return;
    }

    // ------------------------------------------------------------------------
    // MESH FINAL RECIPIENT VALIDATION
    // ------------------------------------------------------------------------
    if (event['mesh_final_recipient'] != true ||
        event['mesh_destination_id']?.toString() !=
            store.deviceId) {
      AppLogger.info(
        'DIRECT_MESH_EVENT_IGNORED',
        detail: 'reason=not_final_recipient',
      );

      return;
    }

    final raw = event['payload']?.toString();

    if (raw == null || raw.isEmpty) {
      AppLogger.warning(
        'DIRECT_MESSAGE_EMPTY_PAYLOAD',
      );

      return;
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) {
        AppLogger.warning(
          'DIRECT_MESSAGE_INVALID_PAYLOAD_TYPE',
        );

        return;
      }

      final data = decoded;

      final type = data['type']?.toString();

      AppLogger.info(
        'DIRECT_MESSAGE_PAYLOAD_PARSED',
        detail:
        'type=${type ?? 'unknown'} '
            'id=${data['id']?.toString() ?? ''}',
      );

      // ----------------------------------------------------------------------
      // DIRECT MESSAGE
      // ----------------------------------------------------------------------
      if (type == 'direct_message') {
        AppLogger.info(
          'DIRECT_MESSAGE_DECRYPT_START',
          detail:
          'id=${data['id']?.toString() ?? ''}',
        );

        final decrypted =
        await _decryptNetworkMessage(data);

        if (decrypted == null) {
          AppLogger.error(
            'DIRECT_MESSAGE_DECRYPT_FAILED',
            detail:
            'id=${data['id']?.toString() ?? ''}',
          );

          return;
        }

        AppLogger.info(
          'DIRECT_MESSAGE_DECRYPT_SUCCESS',
          detail:
          'id=${decrypted.id}',
        );

        var message = decrypted;

        // --------------------------------------------------------------------
        // MESSAGE VALIDATION
        // --------------------------------------------------------------------
        if (message.id.isEmpty ||
            message.senderId.isEmpty ||
            message.recipientId != store.deviceId ||
            await store.isBlockedPeer(
              message.senderId,
            )) {
          AppLogger.warning(
            'DIRECT_MESSAGE_VALIDATION_FAILED',
            detail:
            'id=${message.id}',
          );

          return;
        }

        // --------------------------------------------------------------------
        // RESOLVE DIRECT ATTACHMENTS
        // --------------------------------------------------------------------
        final directAttachments = <Attachment>[];

        for (final attachment in message.attachments) {
          final stored = await store.directFile(
            attachment.id,
          );

          if (stored != null) {
            directAttachments.add(
              attachment.copyWith(
                localPath:
                stored['local_path']?.toString(),
                sha256:
                stored['sha256']?.toString(),
                size:
                int.tryParse(
                  stored['size']?.toString() ?? '',
                ) ??
                    attachment.size,
              ),
            );
          } else {
            final recent =
            _recentDirectFiles[attachment.id];

            directAttachments.add(
              attachment.copyWith(
                localPath:
                recent?['path']?.toString(),
                sha256:
                recent?['sha256']?.toString(),
                size:
                recent?['size'] is int
                    ? recent!['size'] as int
                    : attachment.size,
              ),
            );
          }
        }

        // --------------------------------------------------------------------
        // BUILD DELIVERED MESSAGE
        // --------------------------------------------------------------------
        message = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          body: message.body,
          createdAt: message.createdAt,
          status: 'delivered',
          deliveredAt:
          DateTime.now()
              .toUtc()
              .toIso8601String(),
          serverSeq: message.serverSeq,
          attachments: directAttachments,
        );

        final existed =
        await store.messageExists(
          message.id,
        );

        // --------------------------------------------------------------------
        // SAVE MESSAGE
        // --------------------------------------------------------------------
        await store.saveMessage(message);

        AppLogger.info(
          'DIRECT_MESSAGE_SAVED',
          detail:
          'id=${message.id} '
              'existed=$existed',
        );

        // --------------------------------------------------------------------
        // DELIVERY ACK
        //
        // IMPORTANT:
        // directTransport.send() returns Future<void>.
        // Do NOT assign its result to `ack`.
        // --------------------------------------------------------------------
        try {
          await directTransport.send(
            recipientId: message.senderId,
            payload: {
              'type': 'direct_delivery_ack',
              'id': message.id,
              'sender_id': store.deviceId,
              'recipient_id': message.senderId,
            },
          );

          AppLogger.info(
            'DIRECT_DELIVERY_ACK_SENT',
            detail:
            'id=${message.id} '
                'recipient=${_shortId(message.senderId)}',
          );
        } catch (error, stackTrace) {
          AppLogger.error(
            'DIRECT_DELIVERY_ACK_FAILED',
            error: error,
            stackTrace: stackTrace,
            detail:
            'id=${message.id}',
          );
        }

        // --------------------------------------------------------------------
        // EMIT ONLY NEW MESSAGE
        // --------------------------------------------------------------------
        if (!existed) {
          _incoming.add(message);

          AppLogger.info(
            'DIRECT_MESSAGE_INCOMING_EMITTED',
            detail:
            'id=${message.id}',
          );
        }

        return;
      }

      // ----------------------------------------------------------------------
      // DIRECT DELIVERY ACK
      // ----------------------------------------------------------------------
      if (type == 'direct_delivery_ack') {
        final id = data['id']?.toString();

        if (id == null ||
            id.isEmpty ||
            data['recipient_id']?.toString() !=
                store.deviceId) {
          AppLogger.warning(
            'DIRECT_DELIVERY_ACK_INVALID',
            detail:
            'id=${id ?? ''}',
          );

          return;
        }

        final now = DateTime.now().toUtc();

        // Mark outbox as delivered.
        await store.updateOutboxStatus(
          id,
          'direct_delivered',
        );

        // Update local message status.
        await store.updateMessageStatus(
          id,
          status: 'delivered',
          deliveredAt:
          now.toIso8601String(),
        );

        AppLogger.info(
          'DIRECT_DELIVERY_ACK_PROCESSED',
          detail: 'id=$id',
        );

        final senderId =
            data['sender_id']?.toString() ?? '';

        final local =
        (await store.messagesFor(senderId))
            .where(
              (m) => m.id == id,
        )
            .toList();

        if (local.isNotEmpty &&
            local.first.status != 'delivered') {
          _incoming.add(
            Message(
              id: local.first.id,
              senderId: local.first.senderId,
              recipientId: local.first.recipientId,
              body: local.first.body,
              createdAt: local.first.createdAt,
              status: 'delivered',
              deliveredAt:
              now.toIso8601String(),
              serverSeq: local.first.serverSeq,
              attachments: local.first.attachments,
            ),
          );

          AppLogger.info(
            'DIRECT_DELIVERY_STATUS_EMITTED',
            detail: 'id=$id',
          );
        }

        return;
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'DIRECT_EVENT_PROCESSING_FAILED',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<Attachment>>
  _attachmentsWithDirectFiles(
      List<Attachment> attachments,
      ) async {
    final out = <Attachment>[];

    for (final attachment in attachments) {
      final stored =
      await store.directFile(
        attachment.id,
      );

      out.add(
        stored == null
            ? attachment
            : attachment.copyWith(
          localPath:
          stored['local_path']
              ?.toString(),
          sha256:
          stored['sha256']
              ?.toString(),
          size:
          int.tryParse(
            stored['size']
                ?.toString() ??
                '',
          ) ??
              attachment.size,
        ),
      );
    }

    return out;
  }

  Future<List<Message>> history(
      String otherId,
      ) async {
    AppLogger.info(
      'MESSAGE_HISTORY_START',
      detail:
      'peer=${_shortId(otherId)}',
    );

    final local =
    await store.messagesFor(otherId);

    await synchronize();

    try {
      final remote =
      await api.messages(otherId);

      AppLogger.info(
        'MESSAGE_HISTORY_REMOTE_RECEIVED',
        detail:
        'peer=${_shortId(otherId)} '
            'count=${remote.length}',
      );

      for (final networkMessage in remote) {
        final message =
        await _decryptMessageModel(
          networkMessage,
        );

        if (message != null &&
            !await store.isBlockedPeer(
              message.senderId,
            )) {
          await store.saveMessage(
            message,
          );
        }
      }

      final result =
      await store.messagesFor(otherId);

      AppLogger.info(
        'MESSAGE_HISTORY_SUCCESS',
        detail:
        'peer=${_shortId(otherId)} '
            'count=${result.length}',
      );

      return result;
    } catch (error, stackTrace) {
      AppLogger.error(
        'MESSAGE_HISTORY_REMOTE_FAILED',
        error: error,
        stackTrace: stackTrace,
        detail:
        'peer=${_shortId(otherId)} '
            'returningLocal=true',
      );

      return local;
    }
  }

  Future<void> dispose() async {
    AppLogger.info(
      'MESSAGE_SERVICE_DISPOSE',
    );

    _retryTimer?.cancel();

    await _socketSub?.cancel();
    await _connectionSub?.cancel();
    await _directSub?.cancel();
    await _wifiSub?.cancel();

    await directTransport.dispose();

    await _incoming.close();
  }

  String _newId() {
    final random = Random.secure();

    final suffix = List.generate(
      12,
          (_) => random.nextInt(16).toRadixString(16),
    ).join();

    return '${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }

  String _shortId(String? value) {
    if (value == null || value.isEmpty) {
      return '<none>';
    }

    if (value.length <= 10) {
      return value;
    }

    return '${value.substring(0, 6)}…${value.substring(value.length - 4)}';
  }
}