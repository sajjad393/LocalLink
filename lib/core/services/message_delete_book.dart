import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/models/message_envelope.dart';

/// Bundle 197a: the "never bring back" lists, kept in the settings table as
/// JSON (no database change):
///
/// * deleted message ids (Delete for me, Delete for everyone, and a Delete
///   for everyone that arrived before its message),
/// * cleared chats (chat key -> cleared time, keep the empty row or not).
///
/// Every save path asks [dropsMessage] so an old message can never come back
/// from Online history, a late Nearby copy or a relay.
class MessageDeleteBook extends ChangeNotifier {
  MessageDeleteBook();

  static final MessageDeleteBook instance = MessageDeleteBook();

  static const String deletedKey = 'deleted_messages_197';
  static const String clearsKey = 'chat_clears_197';

  /// Newest ids kept (oldest forgotten first).
  static const int maxDeleted = 2000;

  static const String kindMe = 'me';
  static const String kindAll = 'all';
  static const String kindEarly = 'early';

  Future<String?> Function(String key)? _read;
  Future<void> Function(String key, String value)? _write;

  // Insertion order = age (oldest first).
  final Map<String, DeletedMark> _deleted = <String, DeletedMark>{};
  final Map<String, ChatClear> _clears = <String, ChatClear>{};

  static String directKey(String peerId) => 'd:$peerId';
  static String groupKey(String groupId) => 'g:$groupId';

  int get deletedCount => _deleted.length;

  /// Load once from the settings table (LocalStore.init).
  Future<void> load({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
    DateTime? now,
  }) async {
    _read = read;
    _write = write;
    _deleted.clear();
    _clears.clear();
    final clock = (now ?? DateTime.now()).toUtc();
    try {
      final raw = await read(deletedKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) {
          for (final e in map.entries) {
            final mark = DeletedMark.fromJson(e.value);
            if (mark == null) continue;
            if (mark.kind == kindEarly &&
                clock.difference(mark.savedAt) > kEarlyDeleteKeep) {
              continue; // never arrived in 7 days: forget it
            }
            _deleted[e.key.toString()] = mark;
          }
        }
      }
    } catch (_) {}
    try {
      final raw = await read(clearsKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) {
          for (final e in map.entries) {
            final clear = ChatClear.fromJson(e.value);
            if (clear != null) _clears[e.key.toString()] = clear;
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Account reset / tests: forget everything in memory.
  void resetMemory() {
    _deleted.clear();
    _clears.clear();
    notifyListeners();
  }

  DeletedMark? markFor(String id) => _deleted[id];

  bool isDeleted(String id) {
    final mark = _deleted[id];
    return mark != null && mark.kind != kindEarly;
  }

  ChatClear? clearFor(String chatKey) => _clears[chatKey];

  /// Should a message with this id / chat / time / sender be dropped?
  bool dropsMessage({
    required String id,
    required String chatKey,
    required DateTime createdAt,
    String senderId = '',
  }) {
    final mark = _deleted[id];
    if (mark != null) {
      if (mark.kind != kindEarly) return true;
      // A Delete for everyone came first: accept it only from the real
      // sender and within the time limit.
      final reason = deleteRejectReason(
        command: DeleteCommand(messageId: id, by: mark.by, at: mark.at),
        envelopeSender: mark.by,
        originalSender: senderId,
        originalCreatedAt: createdAt,
      );
      if (reason == null) return true;
    }
    final clear = _clears[chatKey];
    if (clear != null && !createdAt.toUtc().isAfter(clear.at)) return true;
    return false;
  }

  Future<void> markDeleted(
    String id, {
    required String kind,
    String by = '',
    DateTime? at,
    DateTime? now,
  }) async {
    if (id.isEmpty) return;
    final current = _deleted[id];
    // An applied delete never goes back to "early".
    if (current != null && current.kind != kindEarly && kind == kindEarly) {
      return;
    }
    final stamp = (now ?? DateTime.now()).toUtc();
    _deleted.remove(id);
    _deleted[id] = DeletedMark(
      kind: kind,
      by: by,
      at: (at ?? stamp).toUtc(),
      savedAt: stamp,
    );
    while (_deleted.length > maxDeleted) {
      _deleted.remove(_deleted.keys.first);
    }
    await _saveDeleted();
    notifyListeners();
  }

  /// Clear chat (keepRow = true) or Delete chat (keepRow = false).
  Future<void> clearChat(String chatKey,
      {required bool keepRow, DateTime? at}) async {
    if (chatKey.isEmpty) return;
    _clears[chatKey] =
        ChatClear(at: (at ?? DateTime.now()).toUtc(), keepRow: keepRow);
    await _saveClears();
    notifyListeners();
  }

  /// Direct chats cleared with "keep the empty row" (Clear chat).
  Set<String> keptEmptyDirectPeers() => {
        for (final e in _clears.entries)
          if (e.value.keepRow && e.key.startsWith('d:')) e.key.substring(2),
      };

  Future<void> _saveDeleted() async {
    final write = _write;
    if (write == null) return;
    try {
      await write(
          deletedKey,
          jsonEncode({
            for (final e in _deleted.entries) e.key: e.value.toJson(),
          }));
    } catch (_) {}
  }

  Future<void> _saveClears() async {
    final write = _write;
    if (write == null) return;
    try {
      await write(
          clearsKey,
          jsonEncode({
            for (final e in _clears.entries) e.key: e.value.toJson(),
          }));
    } catch (_) {}
  }

  @visibleForTesting
  bool get attached => _read != null;
}

class DeletedMark {
  final String kind;
  final String by;
  final DateTime at;
  final DateTime savedAt;

  const DeletedMark({
    required this.kind,
    required this.by,
    required this.at,
    required this.savedAt,
  });

  List<Object> toJson() =>
      [kind, by, at.millisecondsSinceEpoch, savedAt.millisecondsSinceEpoch];

  static DeletedMark? fromJson(Object? raw) {
    if (raw is! List || raw.length < 4) return null;
    final at = int.tryParse(raw[2].toString());
    final saved = int.tryParse(raw[3].toString());
    if (at == null || saved == null) return null;
    return DeletedMark(
      kind: raw[0].toString(),
      by: raw[1].toString(),
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      savedAt: DateTime.fromMillisecondsSinceEpoch(saved, isUtc: true),
    );
  }
}

class ChatClear {
  final DateTime at;
  final bool keepRow;

  const ChatClear({required this.at, required this.keepRow});

  List<Object> toJson() => [at.millisecondsSinceEpoch, keepRow ? 1 : 0];

  static ChatClear? fromJson(Object? raw) {
    if (raw is! List || raw.length < 2) return null;
    final at = int.tryParse(raw[0].toString());
    if (at == null) return null;
    return ChatClear(
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      keepRow: raw[1].toString() == '1',
    );
  }
}
