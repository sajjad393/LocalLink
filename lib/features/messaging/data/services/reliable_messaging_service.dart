import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/connectivity/domain/local_route.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';

class ReliableMessagingService {
  final LocalStore store;
  final LocalLinkApi api;
  final WebSocketService socket;
  final FileTransferRepositoryContract files;
  final ConnectivityRepositoryContract connectivity;
  final PeerTransportContract directTransport;
  final LocalRoutePolicyService? routePolicy;

  final _incoming = StreamController<Message>.broadcast();
  final _reactionIncoming = StreamController<MessageReaction>.broadcast();
  static const _reactionPrefix = 'llrx:v1:';

  StreamSubscription? _socketSub;
  StreamSubscription? _connectionSub;
  StreamSubscription? _directSub;
  StreamSubscription? _wifiSub;
  StreamSubscription<LocalRouteResult>? _routeSub;
  // Last time the route-listener was allowed to fire a full outbox flush.
  DateTime? _lastRouteFlushAt;

  Timer? _retryTimer;
  Timer? _startupTimer;
  DateTime? _lastPeriodicSyncAt;
  DateTime? _messageRateLimitedUntil;

  bool _syncing = false;
  bool _flushing = false;

  final Map<String, Map<String, dynamic>> _recentDirectFiles = {};

  // Direct (LAN/Wi-Fi Direct/mesh) delivery acks that could not leave this
  // device right now. The mesh queue normally owns this retry
  // (direct_delivery_ack is store-forwardable), but if the native send itself
  // throws — transport restarting, channel momentarily dead — the ack is
  // parked here (message id -> original sender device id) and re-attempted on
  // the next peer_connected/route_recovered event.
  final Map<String, String> _pendingDirectAcks = <String, String>{};
  bool _flushingDirectAcks = false;

  /// [startupSettle] delays the initial sync + realtime connect right after
  /// [start]. On cold launch the main isolate is busy (database keying, first
  /// frame, platform setup); pushing this burst a few seconds later keeps the
  /// first seconds of the UI responsive (prevents ANR during startup debt).
  final Duration _startupSettle;
  bool _disposed = false;

  ReliableMessagingService(this.store, this.api, this.socket, this.files,
      this.connectivity, this.directTransport,
      {this.routePolicy, Duration startupSettle = Duration.zero})
      : _startupSettle = startupSettle;

  Stream<Message> get incoming => _incoming.stream;
  Stream<MessageReaction> get reactionIncoming => _reactionIncoming.stream;

  void start() {
    AppLogger.info(
      'MESSAGE_SERVICE_START',
      detail: 'device=${_shortId(store.deviceId)} '
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

    _routeSub ??= routePolicy?.routeChanges.listen(
      (route) {
        if (!route.isAvailable || store.internetOnly) return;
        // Bundle 52: route changes arrive in bursts (dozens/sec during
        // calls over Wi-Fi Direct). One full DB flush per change starved
        // the store and lined up behind long transactions — the source of
        // the recurring 'database locked' warnings. Coalesce route-
        // triggered flushes; the retry tick remains the guaranteed floor.
        final now = DateTime.now();
        final last = _lastRouteFlushAt;
        if (last != null &&
            now.difference(last) <
                const Duration(seconds: 4)) {
          return;
        }
        _lastRouteFlushAt = now;
        AppLogger.info(
          'MESSAGE_ROUTE_AVAILABLE',
          detail: 'transport=${route.kind.name}',
        );
        unawaited(flush());
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(
          'MESSAGE_ROUTE_STREAM_ERROR',
          error: error,
          stackTrace: stackTrace,
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
          _lastPeriodicSyncAt = DateTime.now().toUtc();
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
      const Duration(seconds: 15),
      (_) async {
        AppLogger.info(
          'MESSAGE_RETRY_TICK',
          detail: 'socket=${socket.isConnected} '
              'direct=${directTransport.isStarted}',
        );

        if (!directTransport.isStarted) {
          await _configureDirectTransport();
        }

        await flush();

        if (socket.isConnected) {
          final now = DateTime.now().toUtc();
          final last = _lastPeriodicSyncAt;
          if (last == null ||
              now.difference(last) >= const Duration(seconds: 60)) {
            _lastPeriodicSyncAt = now;
            await synchronize();
          }
        }
      },
    );

    if (store.serverAddress != null) {
      AppLogger.info(
        'MESSAGE_INITIAL_SYNC',
      );

      _lastPeriodicSyncAt = DateTime.now().toUtc();
      void runInitialBurst() {
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

      if (_startupSettle <= Duration.zero) {
        runInitialBurst();
      } else {
        AppLogger.info(
          'MESSAGE_STARTUP_SETTLE',
          detail: 'delayMs=${_startupSettle.inMilliseconds}',
        );
        _startupTimer = Timer(_startupSettle, () {
          _startupTimer = null;
          if (!_disposed) runInitialBurst();
        });
      }
    }
  }

  Future<void> sendReaction(
      String recipientId, String messageId, String emoji) async {
    final normalized = emoji.trim();
    if (normalized.isEmpty || messageId.trim().isEmpty)
      throw const FormatException('Reaction is required');
    final id = _newId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final payload = jsonEncode({
      'message_id': messageId,
      'emoji': normalized,
      'reactor_id': store.deviceId,
      'created_at': createdAt
    });
    await store.addOutbox({
      'id': id,
      'recipient_id': recipientId,
      'body': '$_reactionPrefix$payload',
      'created_at': createdAt,
      'status': 'queued'
    });
    await store.saveMessageReaction(
        messageId: messageId,
        reactorId: store.deviceId ?? '',
        emoji: normalized,
        createdAt: createdAt);
    _reactionIncoming.add(MessageReaction(
        messageId: messageId,
        reactorId: store.deviceId ?? '',
        emoji: normalized,
        createdAt: DateTime.parse(createdAt).toLocal()));
    await flush();
  }

  Future<List<MessageReaction>> reactions(String messageId) async {
    final rows = await store.messageReactions(messageId);
    return rows
        .map((row) => MessageReaction.fromJson(row))
        .toList(growable: false);
  }

  Future<void> send(
    String recipientId,
    String body, {
    List<PickedFile> attachments = const [],
  }) async {
    AppLogger.info(
      'MESSAGE_SEND_START',
      detail: 'recipient=${_shortId(recipientId)} '
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
        detail: 'id=$id bodyLength=${body.length}',
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

    // Sending to a peer implies a relationship: remember them as a contact
    // (keyed by their directory user) when resolvable.
    unawaited(_autoAddContact(recipientId));

    AppLogger.info(
      'MESSAGE_OUTBOX_CREATED',
      detail: 'id=$id '
          'recipient=${_shortId(recipientId)}',
    );

    final localAttachments = <Attachment>[];

    for (final file in attachments) {
      final fileId = _newId();

      // Bundle 106: stage the picked bytes into durable app-private storage
      // BEFORE queueing. Picker/voice-cache paths can be reclaimed by the OS
      // while the outbox waits offline; without a durable copy the mesh push
      // aborted and the sender's own preview could not render.
      final staged = PickedFile(
        path: await files.stageOutgoingFile(file: file, fileId: fileId),
        name: file.name,
        contentType: file.contentType,
        size: file.size,
      );

      await store.addPendingAttachment(
        id: fileId,
        messageId: id,
        file: staged,
      );

      localAttachments.add(
        Attachment(
          id: fileId,
          originalName: staged.name,
          contentType: staged.contentType,
          size: staged.size,
          sha256: '',
          isImage: staged.contentType.startsWith('image/'),
          localPath: staged.path,
        ),
      );

      AppLogger.info(
        'MESSAGE_ATTACHMENT_QUEUED',
        detail: 'message=$id '
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

    await LocalStore.timedOp(
        'message_save', () => store.saveMessage(message));

    AppLogger.info(
      'MESSAGE_LOCAL_SAVED',
      detail: 'id=$id '
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
      detail: 'cursor=${store.syncCursor ?? '<none>'}',
    );

    try {
      await refreshKnownPeers();

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
          detail: 'messages=${page.messages.length} '
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
          final localPaths = await store.deleteGroupLocal(groupId);

          for (final path in localPaths) {
            await files.deleteLocalFile(path);
          }
        }

        for (final groupMessage in page.groupMessages) {
          await store.saveGroupMessage({
            'id': groupMessage.id,
            'group_id': groupMessage.groupId,
            'sender_id': groupMessage.senderId,
            'body': groupMessage.body,
            'created_at': groupMessage.createdAt,
            'server_seq': groupMessage.serverSeq,
            'attachments':
                groupMessage.attachments.map((a) => a.toJson()).toList(),
          });
        }

        for (final networkMessage in page.messages) {
          AppLogger.info(
            'MESSAGE_SYNC_NETWORK_MESSAGE',
            detail: 'id=${networkMessage.id} '
                'sender=${_shortId(networkMessage.senderId)} '
                'recipient=${_shortId(networkMessage.recipientId)} '
                'status=${networkMessage.status}',
          );

          final message = await _resolveMessage(networkMessage);

          if (message == null) {
            AppLogger.warning(
              'MESSAGE_SYNC_MESSAGE_DROPPED',
              detail: 'id=${networkMessage.id} '
                  'sender=${_shortId(networkMessage.senderId)}',
            );
            continue;
          }
          if (await _consumeReaction(message)) {
            continue;
          }

          if (await store.isBlockedPeer(message.senderId)) {
            AppLogger.warning(
              'MESSAGE_SYNC_BLOCKED_MESSAGE',
              detail: 'id=${message.id} '
                  'sender=${_shortId(message.senderId)}',
            );
            continue;
          }

          final existed = await store.messageExists(message.id);

          await LocalStore.timedOp(
        'message_save', () => store.saveMessage(message));

          AppLogger.info(
            'MESSAGE_SYNC_SAVED',
            detail: 'id=${message.id} '
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
              final delivered = await api.acknowledgeMessage(
                message.id,
              );

              await store.updateMessageStatus(
                delivered.id,
                status: delivered.status,
                deliveredAt: delivered.deliveredAt,
              );

              AppLogger.info(
                'MESSAGE_DELIVERY_ACK_SUCCESS',
                detail: 'id=${message.id} '
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

        if (next != null && next.isNotEmpty) {
          await store.saveSyncCursor(next);
          cursor = next;

          AppLogger.info(
            'MESSAGE_SYNC_CURSOR_UPDATED',
            detail: 'cursorUpdated=true',
          );
        }

        hasMore = page.hasMore;

        if (page.hasMore && (next == null || next.isEmpty)) {
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

  static const _flushWatchdog = Duration(seconds: 60);
  DateTime? _flushStartedAt;

  Future<void> flush() async {
    if (_flushing) {
      // Watchdog: a hung upload/send must not block the queue forever —
      // when the previous flush clearly timed out, force-reset the guard.
      final started = _flushStartedAt;
      if (started != null &&
          DateTime.now().difference(started) > _flushWatchdog) {
        AppLogger.warning('MESSAGE_FLUSH_WATCHDOG_RESET');
        _flushing = false;
      } else {
        AppLogger.info(
          'MESSAGE_FLUSH_SKIPPED_ALREADY_RUNNING',
        );
        return;
      }
    }

    if (!socket.isConnected && !directTransport.isStarted) {
      AppLogger.info(
        'MESSAGE_FLUSH_SKIPPED_NO_TRANSPORT',
      );
      return;
    }

    _flushing = true;
    _flushStartedAt = DateTime.now();
    final messageCooldown = _messageRateLimitedUntil;
    if (messageCooldown != null &&
        DateTime.now().toUtc().isBefore(messageCooldown)) {
      _flushing = false;
      AppLogger.info('MESSAGE_FLUSH_RATE_LIMIT_COOLDOWN',
          detail: 'until=$messageCooldown');
      return;
    }
    _messageRateLimitedUntil = null;

    AppLogger.info(
      'MESSAGE_FLUSH_START',
      detail: 'socket=${socket.isConnected} '
          'direct=${directTransport.isStarted}',
    );

    try {
      final items = await LocalStore.timedOp(
          'outbox_read', () => store.outbox(pendingOnly: true));

      AppLogger.info(
        'MESSAGE_OUTBOX_READ',
        detail: 'count=${items.length}',
      );

      for (final item in items) {
        final id = item['id'].toString();

        final status = item['status']?.toString() ?? 'queued';
        if (!store.isOutboxRetryEligible(item)) {
          AppLogger.info('MESSAGE_RETRY_BACKOFF_SKIP',
              detail: 'id=$id attempt=${item['attempt_count'] ?? 0}');
          continue;
        }

        AppLogger.info(
          'MESSAGE_FLUSH_ITEM',
          detail: 'id=$id '
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

        if (status == 'direct_delivered') {
          await store.removeOutbox(id);
          continue;
        }

        final recipientId = item['recipient_id'].toString();

        final pending = await store.pendingAttachments(id);

        final localRoute = await _localRouteFor(recipientId);
        final canUseDirect =
            !store.internetOnly && localRoute?.isAvailable == true;

        // ------------------------------------------------------------------
        // DIRECT / WI-FI TRANSPORT
        // ------------------------------------------------------------------
        if (canUseDirect) {
          AppLogger.warning(
            'MESSAGE_ROUTE_SELECTED_DIRECT',
            detail: 'socketReady=${socket.isConnected} '
                'internetOnly=${store.internetOnly} '
                'route=${localRoute?.kind.name ?? 'none'}',
          );
          AppLogger.info(
            'MESSAGE_DIRECT_TRANSPORT_SELECTED',
            detail: 'id=$id '
                'recipient=${_shortId(recipientId)}',
          );

          try {
            final attachments = <Map<String, dynamic>>[];

            for (final attachment in pending) {
              final file = PickedFile(
                path: attachment['local_path'].toString(),
                name: attachment['original_name'].toString(),
                contentType: attachment['content_type'].toString(),
                size: int.tryParse(
                      attachment['size'].toString(),
                    ) ??
                    0,
              );

              // Bundle 106: a missing local copy or a Wi-Fi Direct hiccup
              // must not swallow the message — push the bytes best-effort,
              // still send the direct_message, and let the outbox retry the
              // file on the next flush.
              try {
                await files.sendDirectFile(
                  recipientId: recipientId,
                  messageId: id,
                  fileId: attachment['id'].toString(),
                  file: file,
                );
              } catch (error, stackTrace) {
                AppLogger.error(
                  'DIRECT_FILE_PUSH_FAILED',
                  error: error,
                  stackTrace: stackTrace,
                  detail: 'message=$id file=${attachment['id']}',
                );
              }

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

            final body = item['body']?.toString() ?? '';

            // directTransport.send() currently returns void.
            await directTransport.send(
              recipientId: recipientId,
              payload: {
                'type': 'direct_message',
                'id': id,
                'sender_id': store.deviceId,
                'recipient_id': recipientId,
                'body': body,
                'created_at': _rfc3339Utc(item['created_at']),
                if (attachments.isNotEmpty) 'attachments': attachments,
              },
            );

            AppLogger.info(
              'MESSAGE_DIRECT_SEND_ACCEPTED',
              detail: 'id=$id '
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
            'MESSAGE_ROUTE_UNAVAILABLE',
            detail: 'socketReady=${socket.isConnected} '
                'internetOnly=${store.internetOnly} '
                'route=${localRoute?.kind.name ?? 'none'}',
          );
          AppLogger.warning(
            'MESSAGE_SOCKET_SEND_SKIPPED_NOT_CONNECTED',
            detail: 'id=$id',
          );

          continue;
        }

        AppLogger.warning(
          'MESSAGE_ROUTE_SELECTED_SERVER',
          detail: 'socketReady=${socket.isConnected} '
              'internetOnly=${store.internetOnly} '
              'directStarted=${directTransport.isStarted}',
        );
        AppLogger.info(
          'MESSAGE_SERVER_TRANSPORT_SELECTED',
          detail: 'id=$id '
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
              size: int.tryParse(
                    attachment['size'].toString(),
                  ) ??
                  0,
            );

            var uploaded = await files
                .uploadForMessage(
                  picked,
                  recipientId: recipientId,
                  messageId: id,
                  createdAt: item['created_at']?.toString() ?? '',
                  clientFileId: attachment['id']?.toString() ?? '',
                  operationId: id,
                )
                .timeout(const Duration(seconds: 45));

            await store.setPendingRemoteFile(
              attachment['id'].toString(),
              uploaded.id,
            );

            remoteIds.add(uploaded.id);

            AppLogger.info(
              'MESSAGE_ATTACHMENT_UPLOADED',
              detail: 'message=$id '
                  'attachment=${attachment['id']}',
            );
          } catch (error, stackTrace) {
            uploadFailed = true;

            AppLogger.error(
              'MESSAGE_ATTACHMENT_UPLOAD_FAILED',
              error: error,
              stackTrace: stackTrace,
              detail: 'message=$id '
                  'attachment=${attachment['id']}',
            );

            break;
          }
        }

        if (uploadFailed) {
          continue;
        }

        final body = item['body']?.toString() ?? '';
        await store.setOutboxNetworkBody(id, body);

        // socket.send() DOES return bool, so this is valid.
        final sent = socket.send(
          {
            'type': 'send_message',
            'id': id,
            'recipient_id': recipientId,
            'body': body,
            'created_at': _rfc3339Utc(item['created_at']),
            if (remoteIds.isNotEmpty) 'attachment_ids': remoteIds,
          },
          durable: true,
        );

        AppLogger.info(
          'MESSAGE_SERVER_SEND_RESULT',
          detail: 'id=$id '
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

  Future<Message?> _resolveMessage(Message message) async {
    if (message.senderId != store.deviceId) return message;
    final local = await store.messageById(message.id);
    if (local == null) return message;
    return Message(
      id: local.id,
      senderId: local.senderId,
      recipientId: local.recipientId,
      body: local.body,
      createdAt: local.createdAt,
      status: message.status,
      deliveredAt: message.deliveredAt ?? local.deliveredAt,
      serverSeq: message.serverSeq > local.serverSeq
          ? message.serverSeq
          : local.serverSeq,
      attachments: message.attachments.isNotEmpty
          ? _preserveLocalAttachmentPaths(
              message.attachments, local.attachments)
          : local.attachments,
    );
  }

  /// Server history round-trips attachments WITHOUT their local file path.
  /// Blindly taking the server copy makes the sender's own image look
  /// "not downloaded" (download icon instead of the photo). Merge metadata
  /// from the server with the local file path by attachment id.
  List<Attachment> _preserveLocalAttachmentPaths(
      List<Attachment> remote, List<Attachment> local) {
    final byId = <String, String>{
      for (final a in local)
        if ((a.localPath ?? '').isNotEmpty) a.id: a.localPath!,
    };
    if (byId.isEmpty) return remote;
    return [
      for (var i = 0; i < remote.length; i++)
        _withLocalPath(remote[i], byId, local, i),
    ];
  }

  Attachment _withLocalPath(Attachment remote, Map<String, String> byId,
      List<Attachment> local, int i) {
    if ((remote.localPath ?? '').isNotEmpty) return remote;
    var path = byId[remote.id];
    // The server can rekey attachment ids (re-uploaded dedup). Fall back to
    // positional + name pairing so the sender's own copy still renders.
    if (path == null &&
        local.length == 1 &&
        remote.originalName == local[0].originalName) {
      path = byId[local[0].id];
    }
    if (path == null && local.length == 1 && i == 0) {
      path = byId[local[0].id];
    }
    return path == null ? remote : remote.copyWith(localPath: path);
  }

  Future<Message?> _resolveNetworkPayload(Map<String, dynamic> data) async {
    try {
      return _resolveMessage(Message.fromJson(data));
    } catch (error, stackTrace) {
      AppLogger.error('NETWORK_MESSAGE_PARSE_EXCEPTION',
          error: error, stackTrace: stackTrace);
      return null;
    }
  }

  Future<bool> _consumeReaction(Message message) async {
    if (!message.body.startsWith(_reactionPrefix)) return false;
    try {
      final payload =
          jsonDecode(message.body.substring(_reactionPrefix.length));
      if (payload is! Map) return true;
      final messageId = payload['message_id']?.toString() ?? '';
      final emoji = payload['emoji']?.toString() ?? '';
      final reactorId = payload['reactor_id']?.toString() ?? message.senderId;
      final createdAt = payload['created_at']?.toString() ??
          message.createdAt.toUtc().toIso8601String();
      if (messageId.isEmpty || emoji.isEmpty || reactorId != message.senderId)
        return true;
      await store.saveMessageReaction(
          messageId: messageId,
          reactorId: reactorId,
          emoji: emoji,
          createdAt: createdAt);
      _reactionIncoming.add(MessageReaction(
          messageId: messageId,
          reactorId: reactorId,
          emoji: emoji,
          createdAt:
              DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now()));
    } catch (_) {}
    return true;
  }

  Future<void> _handleSocketMessage(
    Map<String, dynamic> data,
  ) async {
    final type = data['type']?.toString();

    final id = data['id']?.toString();

    AppLogger.info(
      'MESSAGE_SOCKET_EVENT',
      detail: 'type=${type ?? 'unknown'} '
          'id=${id ?? ''} '
          'sender=${_shortId(data['sender_id']?.toString())} '
          'recipient=${_shortId(data['recipient_id']?.toString())}',
    );

    if (type == 'error') {
      AppLogger.warning(
        'MESSAGE_SERVER_ERROR_EVENT',
        detail:
            'id=${id ?? ''} error=${data['error']?.toString() ?? 'unknown'}',
      );
      if (id != null && id.isNotEmpty) {
        final errorText = data['error']?.toString().toLowerCase() ?? '';
        final errorCode = data['error_code']?.toString().toUpperCase() ?? '';
        if (errorCode == 'MESSAGE_RATE_LIMITED') {
          final retryAfter =
              int.tryParse(data['retry_after']?.toString() ?? '') ?? 30;
          _messageRateLimitedUntil = DateTime.now().toUtc().add(
                Duration(seconds: retryAfter.clamp(1, 300)),
              );
        }
        if (errorText.contains('created_at') &&
            errorText.contains('required')) {
          // The row's timestamp failed the server's parse/skew gate. Heal it
          // to a server-clock-aligned now and let the retry loop deliver it.
          await store.updateOutboxCreatedAt(id, _rfc3339Utc(null));
        }
        final permanent = errorCode == 'RECIPIENT_NOT_FOUND' ||
            errorCode == 'SENDER_ID_MISMATCH' ||
            errorText.contains('timestamp is invalid') ||
            errorText.contains('too far in the future') ||
            errorText.contains('recipient device not found') ||
            errorText.contains('sender_id does not match') ||
            // The server already owns this id bound to OTHER metadata:
            // retrying can never succeed, so drop it from the queue.
            errorText.contains('already belongs to different');
        await store.updateOutboxStatus(id, permanent ? 'failed' : 'queued');
        AppLogger.info(
          'MESSAGE_ERROR_CLASSIFIED',
          detail: 'id=$id permanent=$permanent code=$errorCode',
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

      final pending = await store.pendingAttachments(id);

      final existed = await store.messageExists(id);

      final base = await _resolveNetworkPayload(data);

      if (base == null) {
        AppLogger.error(
          'MESSAGE_ACK_PAYLOAD_FAILED',
          detail: 'id=$id',
        );

        return;
      }

      final atts = <Attachment>[];

      for (final attachment in base.attachments) {
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
        serverSeq: base.serverSeq,        channel: 'server',
        attachments: atts,
      );

      await store.updateOutboxStatus(
        id,
        'server_accepted',
      );
      AppLogger.info(
        'MESSAGE_SERVER_ACCEPTED',
        detail: 'id=$id',
      );

      await store.saveMessage(
        message,
      );

      await store.removePendingAttachments(
        id,
      );

      // Do NOT delete the sender's local copies: the confirmation path
      // previously wiped the file under the sender's bubble, so the tile
      // flipped from "photo shown" to "download icon" right after the ack.
      // The remote server copy backs up retrieval; the local copy is what
      // WhatsApp-style UX shows. Storage cleanup is handled by the cache
      // sweep, not by the ack path.

      if (!existed) {
        _incoming.add(message);

        AppLogger.info(
          'MESSAGE_ACK_INCOMING_EMITTED',
          detail: 'id=$id',
        );
      }

      AppLogger.info(
        'MESSAGE_ACK_PROCESSED',
        detail: 'id=$id '
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

      final status = data['status']?.toString() ?? 'delivered';

      await store.updateOutboxStatus(
        id,
        status,
      );
      AppLogger.info('MESSAGE_DELIVERY_STATE_UPDATED',
          detail: 'id=$id status=$status');

      await store.updateMessageStatus(
        id,
        status: status,
        deliveredAt: data['created_at']?.toString(),
      );

      AppLogger.info(
        'MESSAGE_DELIVERY_ACK_PROCESSED',
        detail: 'id=$id '
            'status=$status',
      );

      if (status == 'delivered' || status == 'direct_delivered') {
        await store.removeOutbox(id);

        AppLogger.info(
          'MESSAGE_OUTBOX_REMOVED_AFTER_DELIVERY',
          detail: 'id=$id',
        );
      }

      // Push the status refresh into the live message stream — otherwise
      // delivered/read ticks only repaint when the screen is reopened.
      final refreshed = await store.messageById(id);
      if (refreshed != null) {
        _incoming.add(refreshed);
        AppLogger.info(
          'MESSAGE_STATUS_EMITTED',
          detail: 'id=$id status=$status',
        );
      }

      return;
    }

    if (type != 'message') {
      AppLogger.info(
        'MESSAGE_SOCKET_EVENT_IGNORED',
        detail: 'type=${type ?? 'unknown'}',
      );

      return;
    }

    try {
      AppLogger.info(
        'MESSAGE_INCOMING_FROM_SERVER',
        detail: 'id=${id ?? ''}',
      );

      final message = await _resolveNetworkPayload(data);

      if (message != null && message.senderId != store.deviceId) {
        // A server-relayed message implies the peer's client is alive now:
        // count it as liveness for the binary Online window.
        unawaited(store.touchDevicePresence(message.senderId, viaServer: true));
      }
      if (message == null) {
        AppLogger.error(
          'MESSAGE_INCOMING_DROPPED_AFTER_PARSE',
          detail: 'id=${id ?? ''}',
        );

        return;
      }
      if (await _consumeReaction(message)) {
        return;
      }

      if (await store.isBlockedPeer(
        message.senderId,
      )) {
        AppLogger.warning(
          'MESSAGE_INCOMING_BLOCKED_PEER',
          detail: 'id=${message.id} '
              'sender=${_shortId(message.senderId)}',
        );

        return;
      }

      final existed = await store.messageExists(
        message.id,
      );

      await store.saveMessage(
        message,
      );

      AppLogger.info(
        'MESSAGE_INCOMING_SAVED',
        detail: 'id=${message.id} '
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
        detail: 'id=${message.id} '
            'sent=$ackSent',
      );

      if (!existed) {
        _incoming.add(message);

        AppLogger.info(
          'MESSAGE_INCOMING_EMITTED',
          detail: 'id=${message.id}',
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
      final wifiPermissionGranted =
          await connectivity.isWifiDirectPermissionGranted();
      var connected = false;
      var groupOwner = false;
      String? groupOwnerAddress;
      if (wifiPermissionGranted) {
        final info = await connectivity.wifiDirectConnectionInfo();
        connected = info.connected;
        groupOwner = info.groupOwner;
        groupOwnerAddress = info.groupOwnerAddress;
      } else {
        AppLogger.info(
          'DIRECT_TRANSPORT_WIFI_PERMISSION_UNAVAILABLE_LAN_ONLY',
        );
      }

      AppLogger.info(
        'DIRECT_TRANSPORT_INFO',
        detail: 'connected=$connected '
            'groupOwner=$groupOwner '
            'wifiPermission=$wifiPermissionGranted',
      );

      final peers = await store.localDevices();
      final peerIds = peers
          .where((device) => device.revokedAt.isEmpty)
          .map((device) => device.id)
          .toList();

      await directTransport.configure(
        deviceId: store.deviceId!,
        connected: connected,
        groupOwner: groupOwner,
        groupOwnerAddress: groupOwnerAddress,
        knownPeers: peerIds,
      );

      AppLogger.info(
        'DIRECT_TRANSPORT_CONFIGURED',
        detail: 'connected=$connected '
            'knownPeers=${peerIds.length}',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'DIRECT_TRANSPORT_CONFIG_FAILED',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> refreshKnownPeers() async {
    if (store.deviceToken == null || store.serverAddress == null) {
      AppLogger.warning(
        'KNOWN_PEERS_REFRESH_SKIPPED',
      );

      return;
    }

    try {
      AppLogger.info(
        'KNOWN_PEERS_REFRESH_START',
      );

      final peers = await store.localDevices();
      final peerIds = peers
          .where((device) => device.revokedAt.isEmpty)
          .map((device) => device.id)
          .toList();

      await directTransport.updateKnownPeers(peerIds);

      AppLogger.info(
        'KNOWN_PEERS_REFRESH_SUCCESS',
        detail: 'peers=${peerIds.length}',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'KNOWN_PEERS_REFRESH_FAILED',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // Hot-path guardian. During an active call the direct transport emits
  // 100-300 events/sec (mesh_delivered/call_media_received/route_degraded…).
  // developer.log per event is a marshalled platform hop — on the weaker
  // handset that froze the UI for 15-26s at a time (Choreographer megaskips
  // observed in production logcat). We count hot types and flush one summary
  // line per 10s window; rare/interesting event types still log per event.
  // (AppDiagnostics.record() stays per-event — it is in-RAM only.)
  static const Set<String> _hotDirectEventTypes = {
    'call_media_received',
    'mesh_delivered',
    'mesh_queued',
    'call_media_route_degraded',
    'topology',
    'route_invalidated',
    'route_update',
    'link_update',
  };
  final Map<String, int> _hotDirectEventCounts = <String, int>{};
  DateTime? _hotDirectEventWindowStart;

  void _recordHotDirectEvent(String type) {
    final now = DateTime.now();
    final windowStart = _hotDirectEventWindowStart;
    if (windowStart == null) {
      _hotDirectEventWindowStart = now;
    } else if (now.difference(windowStart) >= const Duration(seconds: 10)) {
      if (_hotDirectEventCounts.isNotEmpty) {
        final counts = _hotDirectEventCounts.entries
            .map((e) => '${e.key}=${e.value}')
            .join(' ');
        AppLogger.info('DIRECT_EVENTS_SUMMARY', detail: 'window=10s $counts');
        _hotDirectEventCounts.clear();
      }
      _hotDirectEventWindowStart = now;
    }
    _hotDirectEventCounts[type] = (_hotDirectEventCounts[type] ?? 0) + 1;
  }

  Future<void> _handleDirectEvent(
    Map<String, dynamic> event,
  ) async {
    final eventType = event['type']?.toString() ?? 'unknown';

    if (_hotDirectEventTypes.contains(eventType)) {
      _recordHotDirectEvent(eventType);
    } else {
      AppLogger.info(
        'DIRECT_EVENT_RECEIVED',
        detail: 'type=$eventType '
            'message=${event['message_id']?.toString() ?? ''}',
      );
    }

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
          detail: 'sender=${_shortId(senderId)}',
        );

        return;
      }

      final meta = <String, dynamic>{
        'file_id': fileId,
        'message_id': messageId,
        'path': path,
        'sender_id': senderId,
        'original_name': event['file_name']?.toString() ?? 'attachment',
        'content_type':
            event['content_type']?.toString() ?? 'application/octet-stream',
        'size': int.tryParse(
              event['size']?.toString() ?? '',
            ) ??
            0,
        'sha256': event['sha256']?.toString() ?? '',
      };

      final protectedPath = await files.protectLegacyLocalFile(path!);

      _recentDirectFiles[fileId!] = {
        ...meta,
        'path': protectedPath,
      };

      await store.saveDirectFile(
        fileId: fileId,
        messageId: messageId!,
        senderId: senderId,
        localPath: protectedPath,
        originalName: meta['original_name'] as String,
        contentType: meta['content_type'] as String,
        size: meta['size'] as int,
        sha256: meta['sha256'] as String,
      );

      final messages = await store.messagesFor(senderId);

      for (final message in messages.where(
        (m) => m.id == messageId,
      )) {
        final updated = message.copyWithMessageAttachments(
          await _attachmentsWithDirectFiles(
            message.attachments,
          ),
        );

        await LocalStore.timedOp(
            'message_save_delivered', () => store.saveMessage(updated));

        _incoming.add(updated);

        AppLogger.info(
          'DIRECT_FILE_MESSAGE_UPDATED',
          detail: 'message=$messageId '
              'file=$fileId',
        );
      }

      return;
    }

    // ------------------------------------------------------------------------
    // LINK RECOVERED — RESEND PARKED DELIVERY ACKS
    // A peer reconnect or route recovery is the ideal moment to give acks
    // that could not leave earlier another ride, so queued-up ticks can
    // finally flip to delivered.
    // ------------------------------------------------------------------------
    if (eventType == 'peer_connected' || eventType == 'route_recovered') {
      unawaited(_flushPendingDirectAcks());

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
        event['mesh_destination_id']?.toString() != store.deviceId) {
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
        detail: 'type=${type ?? 'unknown'} '
            'id=${data['id']?.toString() ?? ''}',
      );

      // ----------------------------------------------------------------------
      // DIRECT MESSAGE
      // ----------------------------------------------------------------------
      if (type == 'direct_message') {
        AppLogger.info(
          'DIRECT_MESSAGE_PAYLOAD_START',
          detail: 'id=${data['id']?.toString() ?? ''}',
        );

        final decrypted = await _resolveNetworkPayload(data);

        if (decrypted == null) {
          AppLogger.error(
            'DIRECT_MESSAGE_PAYLOAD_FAILED',
            detail: 'id=${data['id']?.toString() ?? ''}',
          );

          return;
        }
        if (await _consumeReaction(decrypted)) {
          return;
        }

        AppLogger.info(
          'DIRECT_MESSAGE_PAYLOAD_SUCCESS',
          detail: 'id=${decrypted.id}',
        );

        var message = decrypted.copyWithChannel('direct');

        // --------------------------------------------------------------------
        // MESSAGE VALIDATION
        // --------------------------------------------------------------------
        final hasMessageId = message.id.isNotEmpty;
        final hasSenderId = message.senderId.isNotEmpty;
        final recipientMatchesLocalDevice =
            message.recipientId == store.deviceId;
        final senderBlocked =
            hasMessageId && hasSenderId && recipientMatchesLocalDevice
                ? await store.isBlockedPeer(message.senderId)
                : false;
        if (!hasMessageId ||
            !hasSenderId ||
            !recipientMatchesLocalDevice ||
            senderBlocked) {
          AppLogger.warning(
            'DIRECT_MESSAGE_VALIDATION_FAILED',
            detail: 'hasMessageId=$hasMessageId '
                'hasSenderId=$hasSenderId '
                'recipientMatchesLocalDevice=$recipientMatchesLocalDevice '
                'senderBlocked=$senderBlocked',
          );

          return;
        }

        // A peer that messages us belongs in the local contact list: add them
        // by directory user (once) so conversations start from a known person.
        unawaited(_autoAddContact(message.senderId));

        // Mesh delivery just proved the peer is alive: refresh its binary
        // presence stamp (our clock, not theirs).
        unawaited(store.touchDevicePresence(message.senderId, viaMesh: true));

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
                localPath: stored['local_path']?.toString(),
                sha256: stored['sha256']?.toString(),
                size: int.tryParse(
                      stored['size']?.toString() ?? '',
                    ) ??
                    attachment.size,
              ),
            );
          } else {
            final recent = _recentDirectFiles[attachment.id];

            directAttachments.add(
              attachment.copyWith(
                localPath: recent?['path']?.toString(),
                sha256: recent?['sha256']?.toString(),
                size: recent?['size'] is int
                    ? recent!['size'] as int
                    : attachment.size,
              ),
            );
          }
        }

        // --------------------------------------------------------------------
        // NORMALIZE SKEWED CLOCK
        //
        // In server mode the server stamp dominates ordering, so a drifting
        // phone clock never scrambles the timeline. In direct mode there is
        // no neutral clock: messages sort strictly by the SENDER's
        // created_at, and two phones hours apart interleave every rapid
        // back-and-forth burst into a visually "mixed up" chat. Received
        // messages join the timeline in ARRIVAL order (WhatsApp-style), so
        // when the peer's stamp disagrees with our clock by more than ~90s
        // we re-stamp it at local receipt time.
        // --------------------------------------------------------------------
        final receivedAtUtc = DateTime.now().toUtc();
        final stampDrift = message.createdAt.difference(receivedAtUtc).abs();
        final normalizedCreatedAt = stampDrift > const Duration(seconds: 90)
            ? receivedAtUtc
            : message.createdAt;

        // --------------------------------------------------------------------
        // BUILD DELIVERED MESSAGE
        // --------------------------------------------------------------------
        message = Message(
          id: message.id,
          senderId: message.senderId,
          recipientId: message.recipientId,
          body: message.body,
          createdAt: normalizedCreatedAt,
          status: 'delivered',
          deliveredAt: receivedAtUtc.toIso8601String(),
          serverSeq: message.serverSeq,
          attachments: directAttachments,
        );

        final existed = await store.messageExists(
          message.id,
        );

        // --------------------------------------------------------------------
        // SAVE MESSAGE
        // --------------------------------------------------------------------
        await LocalStore.timedOp(
        'message_save', () => store.saveMessage(message));

        AppLogger.info(
          'DIRECT_MESSAGE_SAVED',
          detail: 'id=${message.id} '
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
            detail: 'id=${message.id} '
                'recipient=${_shortId(message.senderId)}',
          );
        } catch (error, stackTrace) {
          AppLogger.error(
            'DIRECT_DELIVERY_ACK_FAILED',
            error: error,
            stackTrace: stackTrace,
            detail: 'id=${message.id}',
          );

          // Park the ack — the next route recovery resends it, so the
          // sender's tick can still flip to delivered.
          if (_pendingDirectAcks.length < 128) {
            _pendingDirectAcks[message.id] = message.senderId;
            AppLogger.info(
              'DIRECT_DELIVERY_ACK_QUEUED',
              detail: 'id=${message.id} '
                  'pending=${_pendingDirectAcks.length}',
            );
          }
        }

        // --------------------------------------------------------------------
        // EMIT ONLY NEW MESSAGE
        // --------------------------------------------------------------------
        if (!existed) {
          _incoming.add(message);

          AppLogger.info(
            'DIRECT_MESSAGE_INCOMING_EMITTED',
            detail: 'id=${message.id}',
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
            data['recipient_id']?.toString() != store.deviceId) {
          AppLogger.warning(
            'DIRECT_DELIVERY_ACK_INVALID',
            detail: 'id=${id ?? ''}',
          );

          return;
        }

        // Their ack travelled back over the mesh: the acking peer is alive.
        unawaited(store.touchDevicePresence(data['sender_id']?.toString() ?? '',
            viaMesh: true));

        final now = DateTime.now().toUtc();

        // The message has reached the recipient: drop it from the outbox so
        // the retry pipeline no longer tracks it. The delivered state itself
        // is recorded on the message row below. (Previously this only set the
        // outbox status to 'direct_delivered', which left stale rows behind
        // because outbox(pendingOnly: true) already excludes them.)
        await store.removeOutbox(id);

        // Update local message status.
        await store.updateMessageStatus(
          id,
          status: 'delivered',
          deliveredAt: now.toIso8601String(),
        );

        AppLogger.info(
          'DIRECT_DELIVERY_ACK_PROCESSED',
          detail: 'id=$id',
        );

        // Push the status refresh into the live message stream, exactly like
        // the websocket delivery_ack handler above. The previous version
        // gated the emit on `status != 'delivered'` AFTER persisting
        // 'delivered' — a condition that could never be true — so direct-mode
        // ticks stayed stuck at the pending clock until the screen reloaded.
        final refreshed = await store.messageById(id);
        if (refreshed != null) {
          _incoming.add(refreshed);

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

  Future<void> _flushPendingDirectAcks() async {
    if (_flushingDirectAcks || _pendingDirectAcks.isEmpty) return;
    _flushingDirectAcks = true;
    try {
      for (final entry in _pendingDirectAcks.entries.toList()) {
        try {
          await directTransport.send(
            recipientId: entry.value,
            payload: {
              'type': 'direct_delivery_ack',
              'id': entry.key,
              'sender_id': store.deviceId,
              'recipient_id': entry.value,
            },
          );
          _pendingDirectAcks.remove(entry.key);
          AppLogger.info(
            'DIRECT_DELIVERY_ACK_RESENT',
            detail: 'id=${entry.key}',
          );
        } catch (_) {
          // Link went right back down: keep the ack parked and stop
          // hammering a dead socket — the next recovery retries everything.
          AppLogger.info(
            'DIRECT_DELIVERY_ACK_RESEND_DEFERRED',
            detail: 'id=${entry.key} '
                'pending=${_pendingDirectAcks.length}',
          );
          break;
        }
      }
    } finally {
      _flushingDirectAcks = false;
    }
  }

  Future<List<Attachment>> _attachmentsWithDirectFiles(
    List<Attachment> attachments,
  ) async {
    final out = <Attachment>[];

    for (final attachment in attachments) {
      final stored = await store.directFile(
        attachment.id,
      );

      out.add(
        stored == null
            ? attachment
            : attachment.copyWith(
                localPath: stored['local_path']?.toString(),
                sha256: stored['sha256']?.toString(),
                size: int.tryParse(
                      stored['size']?.toString() ?? '',
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
      detail: 'peer=${_shortId(otherId)}',
    );

    final local = await store.messagesFor(otherId);

    await synchronize();

    try {
      final remote = await api.messages(otherId);

      AppLogger.info(
        'MESSAGE_HISTORY_REMOTE_RECEIVED',
        detail: 'peer=${_shortId(otherId)} '
            'count=${remote.length}',
      );

      for (final networkMessage in remote) {
        final message = await _resolveMessage(networkMessage);

        // Reaction control envelopes must never surface as chat bubbles —
        // history() previously leaked them to the UI (llrx:v1:{...}).
        if (message != null && await _consumeReaction(message)) continue;

        if (message != null &&
            !await store.isBlockedPeer(
              message.senderId,
            )) {
          await store.saveMessage(
            message,
          );
        }
      }

      final result = await store.messagesFor(otherId);

      AppLogger.info(
        'MESSAGE_HISTORY_SUCCESS',
        detail: 'peer=${_shortId(otherId)} '
            'count=${result.length}',
      );

      return result;
    } catch (error, stackTrace) {
      AppLogger.error(
        'MESSAGE_HISTORY_REMOTE_FAILED',
        error: error,
        stackTrace: stackTrace,
        detail: 'peer=${_shortId(otherId)} '
            'returningLocal=true',
      );

      return local;
    }
  }

  Future<void> dispose() async {
    AppLogger.info(
      'MESSAGE_SERVICE_DISPOSE',
    );

    _disposed = true;
    _startupTimer?.cancel();
    _retryTimer?.cancel();

    await _socketSub?.cancel();
    await _connectionSub?.cancel();
    await _directSub?.cancel();
    await _wifiSub?.cancel();
    await _routeSub?.cancel();

    await _reactionIncoming.close();
    await directTransport.dispose();

    await _incoming.close();
  }

  Future<LocalRouteResult?> _localRouteFor(String recipientId) async {
    if (store.internetOnly || !directTransport.isStarted) return null;
    final policy = routePolicy;
    if (policy == null) {
      // Preserve compatibility for callers that have not yet migrated to the
      // application-scoped policy service.
      return LocalRouteResult(
        kind: LocalRouteKind.mesh,
        peerId: recipientId,
        transportState: LocalTransportState.available,
      );
    }
    try {
      return await policy.resolve(recipientId);
    } catch (error, stackTrace) {
      AppLogger.error(
        'MESSAGE_ROUTE_RESOLUTION_FAILED',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Adds the directory user that owns [deviceId] to the local contacts if
  /// they are not already present. Contacts are keyed by user id so a user
  /// with several devices never produces duplicate contacts. Peers that
  /// cannot be resolved through the directory are left untouched.
  Future<void> _autoAddContact(String deviceId) async {
    try {
      final profile = await store.directoryProfileByDeviceId(deviceId);
      final userId = profile?['user_id']?.toString().trim() ?? '';
      if (userId.isEmpty) return;
      if (await store.isContact(userId)) return;
      await store.addContact(userId, deviceId);
      AppLogger.info(
        'CONTACT_AUTO_ADDED',
        detail: 'device=${_shortId(deviceId)}',
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'CONTACT_AUTO_ADD_FAILED',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Always emit a server-acceptable timestamp (RFC3339, UTC, Z suffix).
  /// Outbox rows created by older builds may hold local-format ISO strings
  /// (no Z) which the Go server cannot parse -> "valid created_at is
  /// required" and permanent re-queue loops. Normalize at the send site.
  /// Always emit a server-acceptable timestamp: parseable, UTC, and never
  /// ahead of the SERVER clock by more than the skew gate allows. Device
  /// clocks on manual-time phones can run minutes fast; the offset learned
  /// from the websocket `ready` frame keeps us inside the 10-minute window
  /// (with a built-in 2-minute margin).
  String _rfc3339Utc(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    var value = (parsed ?? DateTime.now()).toUtc();
    final offset = socket.serverClockOffset;
    if (offset != null) {
      final serverNow = DateTime.now().toUtc().add(offset);
      final ceiling = serverNow.add(const Duration(minutes: 8));
      if (value.isAfter(ceiling)) {
        AppLogger.warning(
          'MESSAGE_CLOCK_CLAMPED',
          detail: 'drift=${value.difference(serverNow).inSeconds}s',
        );
        value = serverNow;
      }
    }
    return value.toIso8601String();
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
