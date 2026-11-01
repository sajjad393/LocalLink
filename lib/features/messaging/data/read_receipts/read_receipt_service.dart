import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/message_delete_book.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipts_setting.dart';

/// Bundle 198: the reader's side. Collects "I read" / "I played" ids per
/// chat and sends ONE hidden `llread:v1:` note per chat after a short
/// quiet time (through the normal message path: Nearby, Online, relays,
/// outbox). 1-to-1 only.
class ReadReceiptService {
  ReadReceiptService({
    required this.localId,
    required this.send,
    required this.isBlocked,
    required this.markPlayed,
    required this.messageById,
    ReadReceiptsSetting? setting,
    MessageDeleteBook? deletes,
    this.quiet = const Duration(seconds: 2),
  })  : setting = setting ?? ReadReceiptsSetting.instance,
        deletes = deletes ?? MessageDeleteBook.instance;

  final String? Function() localId;
  final Future<void> Function(String peerId, ReadCommand command) send;
  final Future<bool> Function(String peerId) isBlocked;

  /// True only the first time I play that voice note.
  final Future<bool> Function(String messageId) markPlayed;
  final Future<Message?> Function(String messageId) messageById;
  final ReadReceiptsSetting setting;
  final MessageDeleteBook deletes;
  final Duration quiet;

  final Map<String, _Batch> _pending = <String, _Batch>{};
  final Map<String, Timer> _timers = <String, Timer>{};
  bool _disposed = false;

  static String _short(String id) =>
      id.length > 6 ? id.substring(id.length - 6) : id;

  /// A friend's message became read on this phone (chat open, notification
  /// Reply / Mark as read / Open). Switch OFF = nothing.
  void noteRead(Message m) {
    if (_disposed || !setting.on) return;
    final me = localId();
    if (me == null || me.isEmpty) return;
    if (m.id.isEmpty || m.senderId.isEmpty || m.senderId == me) return;
    if (m.recipientId != me) return;
    if (MessageEnvelope.isControl(m.body)) return;
    if (deletes.isDeleted(m.id)) return;
    _add(m.senderId, read: m.id);
  }

  /// I started playing a friend's voice note (first play only). Works also
  /// when the switch is OFF (WhatsApp rule).
  Future<void> notePlayed(String messageId) async {
    if (_disposed || messageId.isEmpty) return;
    try {
      final me = localId();
      final m = await messageById(messageId);
      if (m == null || me == null || m.senderId == me || m.recipientId != me) {
        return;
      }
      if (!await markPlayed(messageId)) return;
      AppLogger.info('VOICE_PLAYED_NOTED', detail: 'id=${_short(messageId)}');
      _add(m.senderId, played: messageId);
    } catch (error) {
      AppLogger.warning('VOICE_PLAYED_FAILED', detail: '$error');
    }
  }

  void _add(String peer, {String? read, String? played}) {
    final batch = _pending.putIfAbsent(peer, _Batch.new);
    if (read != null) batch.read.add(read);
    if (played != null) batch.played.add(played);
    _timers[peer] ??= Timer(quiet, () {
      _timers.remove(peer);
      unawaited(_flush(peer));
    });
  }

  Future<void> _flush(String peer) async {
    final batch = _pending.remove(peer);
    if (batch == null || batch.isEmpty || _disposed) return;
    try {
      if (await isBlocked(peer)) return;
      final played = batch.played.take(kReadReceiptMaxIds).toList();
      final room = kReadReceiptMaxIds - played.length;
      final read = batch.read
          .where((id) => !batch.played.contains(id))
          .take(room)
          .toList();
      // More than fits: the rest goes in the next note.
      final restPlayed = batch.played.skip(played.length).toList();
      final restRead = batch.read
          .where((id) => !batch.played.contains(id))
          .skip(read.length)
          .toList();
      if (restPlayed.isNotEmpty || restRead.isNotEmpty) {
        for (final id in restPlayed) {
          _add(peer, played: id);
        }
        for (final id in restRead) {
          _add(peer, read: id);
        }
      }
      final command = ReadCommand(
          read: read, played: played, at: DateTime.now().toUtc());
      if (command.isEmpty) return;
      await send(peer, command);
      AppLogger.info('READ_RECEIPT_SENT',
          detail: 'chat=${_short(peer)} read=${command.read.length} '
              'played=${command.played.length}');
    } catch (error) {
      AppLogger.warning('READ_RECEIPT_SEND_FAILED', detail: '$error');
    }
  }

  @visibleForTesting
  Future<void> flushAllForTest() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    for (final peer in _pending.keys.toList()) {
      await _flush(peer);
    }
  }

  @visibleForTesting
  int get pendingChats => _pending.length;

  void dispose() {
    _disposed = true;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _pending.clear();
  }
}

class _Batch {
  final Set<String> read = <String>{};
  final Set<String> played = <String>{};
  bool get isEmpty => read.isEmpty && played.isEmpty;
}
