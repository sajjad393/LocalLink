import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bundle G5: receipts per member, Message info and "typing" for groups.
///
/// Rules (mock 19 / 20 / 15):
/// * ✓ = sent (server took it, or it went Nearby).
/// * ✓✓ grey only when every other member got it.
/// * ✓✓ blue only when every other member read it.
/// * People with read receipts off show under "Delivered".
/// * With my own read receipts off I send no "read" and see no blue (the
///   same rule as 1-to-1, bundle 198).

class GroupReceipt {
  const GroupReceipt({
    required this.messageId,
    required this.deviceId,
    this.deliveredAt,
    this.readAt,
  });

  final String messageId;
  final String deviceId;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  factory GroupReceipt.fromRow(Map<String, dynamic> row) {
    DateTime? at(Object? v) {
      final text = v?.toString() ?? '';
      return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
    }

    final read = at(row['read_at']);
    return GroupReceipt(
      messageId: row['message_id']?.toString() ?? '',
      deviceId: row['device_id']?.toString() ?? '',
      deliveredAt: at(row['delivered_at']) ?? read,
      readAt: read,
    );
  }
}

enum GroupTick { pending, sent, delivered, read }

/// message id -> member id -> receipt.
Map<String, Map<String, GroupReceipt>> groupReceiptsByMessage(
    Iterable<Map<String, dynamic>> rows) {
  final out = <String, Map<String, GroupReceipt>>{};
  for (final row in rows) {
    final r = GroupReceipt.fromRow(row);
    if (r.messageId.isEmpty || r.deviceId.isEmpty) continue;
    (out[r.messageId] ??= <String, GroupReceipt>{})[r.deviceId] = r;
  }
  return out;
}

/// The tick under one of MY messages. [others] = the members now, without me.
GroupTick groupTickFor({
  required bool sent,
  required Set<String> others,
  Map<String, GroupReceipt>? receipts,
  bool readsOn = true,
}) {
  if (!sent) return GroupTick.pending;
  if (others.isEmpty) return GroupTick.sent;
  final rows = receipts ?? const <String, GroupReceipt>{};
  final all = others.every((id) => rows[id]?.deliveredAt != null);
  if (!all) return GroupTick.sent;
  if (readsOn && others.every((id) => rows[id]?.readAt != null)) {
    return GroupTick.read;
  }
  return GroupTick.delivered;
}

class GroupInfoPerson {
  const GroupInfoPerson(this.deviceId, this.name, this.at);
  final String deviceId;
  final String name;
  final DateTime? at;
}

/// What the "Message info" sheet lists (mock 19 / 20).
class GroupMessageInfo {
  const GroupMessageInfo({
    required this.total,
    required this.read,
    required this.delivered,
    required this.waiting,
  });

  final int total;
  final List<GroupInfoPerson> read;
  final List<GroupInfoPerson> delivered;
  final List<GroupInfoPerson> waiting;

  int get gotIt => read.length + delivered.length;

  /// [others] = member id -> name (without me).
  factory GroupMessageInfo.build({
    required Map<String, String> others,
    Map<String, GroupReceipt>? receipts,
    bool readsOn = true,
  }) {
    final rows = receipts ?? const <String, GroupReceipt>{};
    final read = <GroupInfoPerson>[];
    final delivered = <GroupInfoPerson>[];
    final waiting = <GroupInfoPerson>[];
    others.forEach((id, name) {
      final r = rows[id];
      if (readsOn && r?.readAt != null) {
        read.add(GroupInfoPerson(id, name, r!.readAt));
      } else if (r?.deliveredAt != null) {
        delivered.add(GroupInfoPerson(id, name, r!.deliveredAt));
      } else {
        waiting.add(GroupInfoPerson(id, name, null));
      }
    });
    int byTime(GroupInfoPerson a, GroupInfoPerson b) {
      final t = (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0));
      return t != 0 ? t : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    read.sort(byTime);
    delivered.sort(byTime);
    waiting.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return GroupMessageInfo(
        total: others.length, read: read, delivered: delivered, waiting: waiting);
  }
}

/// "Sara is typing…" / "Sara and Bilal are typing…" / "3 people are typing…".
String groupTypingText(List<String> names) {
  final clean = names.where((n) => n.trim().isNotEmpty).toList();
  if (clean.isEmpty) return '';
  if (clean.length == 1) return '${clean.first} is typing…';
  if (clean.length == 2) return '${clean[0]} and ${clean[1]} are typing…';
  return '${clean.length} people are typing…';
}

/// Who is typing in which group (server road). A typing note lasts 6 s
/// unless renewed; "stopped" or a message from that person ends it.
class GroupTypingBook {
  GroupTypingBook({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const Duration life = Duration(seconds: 6);

  final DateTime Function() _clock;
  final Map<String, Map<String, DateTime>> _until = {};
  final _changes = StreamController<String>.broadcast();
  final Map<String, Timer> _timers = {};

  Stream<String> get changes => _changes.stream;

  void note(String groupId, String deviceId, bool on) {
    if (groupId.isEmpty || deviceId.isEmpty) return;
    final map = _until[groupId] ??= <String, DateTime>{};
    final had = map.containsKey(deviceId);
    if (on) {
      map[deviceId] = _clock().add(life);
      _timers[groupId]?.cancel();
      _timers[groupId] = Timer(life + const Duration(milliseconds: 50), () {
        _timers.remove(groupId);
        if (_sweep(groupId)) _changes.add(groupId);
      });
      if (!had) _changes.add(groupId);
    } else if (had) {
      map.remove(deviceId);
      _changes.add(groupId);
    }
  }

  bool _sweep(String groupId) {
    final map = _until[groupId];
    if (map == null) return false;
    final now = _clock();
    final before = map.length;
    map.removeWhere((_, until) => !until.isAfter(now));
    return map.length != before;
  }

  /// Members typing now, oldest first.
  List<String> typing(String groupId) {
    _sweep(groupId);
    final map = _until[groupId];
    if (map == null) return const [];
    return map.keys.toList();
  }

  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
}

/// When to send "I am typing" from the composer: at most one "on" per 3 s,
/// and "off" after 5 s without a key or when the message is sent.
class GroupTypingSender {
  GroupTypingSender(this._send, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final void Function(bool on) _send;
  final DateTime Function() _clock;
  DateTime? _lastOn;
  Timer? _idle;
  bool _on = false;

  void changed(String text) {
    if (text.trim().isEmpty) {
      stop();
      return;
    }
    final now = _clock();
    if (!_on || _lastOn == null || now.difference(_lastOn!) >= const Duration(seconds: 3)) {
      _on = true;
      _lastOn = now;
      _send(true);
    }
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 5), stop);
  }

  void stop() {
    _idle?.cancel();
    _idle = null;
    if (!_on) return;
    _on = false;
    _lastOn = null;
    _send(false);
  }

  void dispose() {
    _idle?.cancel();
    _idle = null;
  }
}

/// Lets the chat screen reach the receipts / typing parts of the group
/// service without changing the repository contracts (5 test fakes).
class GroupReceiptHub {
  GroupReceiptHub._();

  /// message id -> member id -> receipt, for one group.
  static Future<Map<String, Map<String, GroupReceipt>>> Function(String groupId)?
      load;

  /// A receipt changed in this group.
  static Stream<String> Function()? changes;

  /// The chat is open: tell writers "read" (when my switch is on).
  static Future<void> Function(String groupId)? markRead;

  /// Ask the server again (Message info opened).
  static Future<void> Function(String groupId)? refresh;

  static void Function(String groupId, bool on)? sendTyping;
  static List<String> Function(String groupId)? typing;
  static Stream<String> Function()? typingChanges;

  /// Goes up on every typing change (Chats list listens; never reset).
  static final ValueNotifier<int> typingVersion = ValueNotifier<int>(0);

  static void reset() {
    load = null;
    changes = null;
    markRead = null;
    refresh = null;
    sendTyping = null;
    typing = null;
    typingChanges = null;
  }
}
