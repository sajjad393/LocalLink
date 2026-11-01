import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Bundle 196 (12b): a Nearby "Add friend" that waits for the private
/// person's answer. Example: sumaira is private, Ali taps Add friend.
/// On sumaira's phone the request waits here (24 h); on Ali's phone the
/// button says "Requested" (24 h).
class FriendRequest {
  final String deviceId;
  final String userId;
  final String name;
  final String username;
  final int atMs;

  /// The signed pair body exactly as it came (checked again on Accept).
  final String body;

  /// Declined: kept (silent) so the same phone gets "wait" again, but no
  /// row and no notice.
  final bool declined;

  const FriendRequest({
    required this.deviceId,
    required this.userId,
    required this.name,
    required this.username,
    required this.atMs,
    required this.body,
    this.declined = false,
  });

  FriendRequest copyWith({bool? declined, String? body}) => FriendRequest(
        deviceId: deviceId,
        userId: userId,
        name: name,
        username: username,
        atMs: atMs,
        body: body ?? this.body,
        declined: declined ?? this.declined,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'd': deviceId,
        'u': userId,
        'n': name,
        'un': username,
        'at': atMs,
        'b': body,
        if (declined) 'x': 1,
      };

  static FriendRequest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final d = raw['d']?.toString().trim() ?? '';
    final at = int.tryParse(raw['at']?.toString() ?? '') ?? 0;
    final b = raw['b']?.toString() ?? '';
    if (d.isEmpty || at <= 0 || b.isEmpty) return null;
    return FriendRequest(
      deviceId: d,
      userId: raw['u']?.toString() ?? '',
      name: raw['n']?.toString() ?? '',
      username: raw['un']?.toString() ?? '',
      atMs: at,
      body: b,
      declined: raw['x']?.toString() == '1',
    );
  }
}

class FriendRequestRules {
  FriendRequestRules._();

  static const String incomingKey = 'friend_requests_waiting';
  static const String sentKey = 'friend_requests_sent';
  static const int lifetimeMs = 24 * 60 * 60 * 1000;
  static const int maxEntries = 50;

  static bool alive(int atMs, int nowMs) =>
      atMs > 0 && nowMs - atMs < lifetimeMs && atMs <= nowMs + 120000;

  static Map<String, FriendRequest> decodeIncoming(String? raw,
      {required int nowMs}) {
    final out = <String, FriendRequest>{};
    if (raw == null || raw.trim().isEmpty) return out;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return out;
      for (final row in list) {
        final r = FriendRequest.fromJson(row);
        if (r != null && alive(r.atMs, nowMs)) out[r.deviceId] = r;
      }
    } catch (_) {}
    return out;
  }

  static String encodeIncoming(Map<String, FriendRequest> all) {
    final list = all.values.toList()..sort((a, b) => b.atMs.compareTo(a.atMs));
    return jsonEncode([for (final r in list.take(maxEntries)) r.toJson()]);
  }

  /// Sent requests: deviceId -> {u: userId, at}.
  static Map<String, (String, int)> decodeSent(String? raw,
      {required int nowMs}) {
    final out = <String, (String, int)>{};
    if (raw == null || raw.trim().isEmpty) return out;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return out;
      map.forEach((k, v) {
        if (k is! String || k.isEmpty || v is! Map) return;
        final at = int.tryParse(v['at']?.toString() ?? '') ?? 0;
        if (alive(at, nowMs)) out[k] = (v['u']?.toString() ?? '', at);
      });
    } catch (_) {}
    return out;
  }

  static String encodeSent(Map<String, (String, int)> all) {
    final list = all.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    return jsonEncode({
      for (final e in list.take(maxEntries))
        e.key: {'u': e.value.$1, 'at': e.value.$2},
    });
  }

  /// "<1 min" / "5 min" / "2 h" for the Requests row.
  static String age(int atMs, int nowMs) {
    final m = ((nowMs - atMs) / 60000).floor();
    if (m < 1) return '<1 min';
    if (m < 60) return '$m min';
    return '${(m / 60).floor()} h';
  }
}

/// Bundle 196 (12b): the one place both lists live (app-wide, like
/// PresenceHub). Saved in settings, so a restart keeps them.
class FriendRequestBook extends ChangeNotifier {
  FriendRequestBook._();

  static FriendRequestBook instance = FriendRequestBook._();

  /// Tests: a fresh book.
  static void resetForTest() => instance = FriendRequestBook._();

  Future<String?> Function(String key)? _read;
  Future<void> Function(String key, String value)? _write;
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  Map<String, FriendRequest> _incoming = <String, FriendRequest>{};
  Map<String, (String, int)> _sent = <String, (String, int)>{};

  /// Accept / Decline from the People tab or the notification
  /// (argument = the asking phone's device id). Set by the app wiring.
  Future<void> Function(String deviceId)? onAccept;
  Future<void> Function(String deviceId)? onDecline;

  /// How many Nearby lists are on screen (the accepted chat opens by
  /// itself only then).
  int nearbyOnScreen = 0;

  Future<void> attach({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    _read = read;
    _write = write;
    await reload();
  }

  Future<void> reload() async {
    final r = _read;
    if (r == null) return;
    try {
      final t = now();
      _incoming = FriendRequestRules.decodeIncoming(
          await r(FriendRequestRules.incomingKey),
          nowMs: t);
      _sent = FriendRequestRules.decodeSent(await r(FriendRequestRules.sentKey),
          nowMs: t);
      notifyListeners();
    } catch (_) {}
  }

  void _prune() {
    final t = now();
    _incoming.removeWhere((_, r) => !FriendRequestRules.alive(r.atMs, t));
    _sent.removeWhere((_, v) => !FriendRequestRules.alive(v.$2, t));
  }

  Future<void> _save() async {
    final w = _write;
    if (w == null) return;
    try {
      await w(FriendRequestRules.incomingKey,
          FriendRequestRules.encodeIncoming(_incoming));
      await w(FriendRequestRules.sentKey, FriendRequestRules.encodeSent(_sent));
    } catch (_) {}
  }

  /// Requests to show (not declined), newest first.
  List<FriendRequest> get visible {
    _prune();
    final list = _incoming.values.where((r) => !r.declined).toList()
      ..sort((a, b) => b.atMs.compareTo(a.atMs));
    return list;
  }

  FriendRequest? incoming(String deviceId) {
    _prune();
    return _incoming[deviceId];
  }

  /// Saves a request. Returns true only when it is new (show the notice):
  /// the same phone asking again inside 24 h (or after Decline) is quiet.
  Future<bool> addIncoming(FriendRequest r) async {
    _prune();
    final old = _incoming[r.deviceId];
    if (old != null) {
      _incoming[r.deviceId] = old.copyWith(body: r.body);
      await _save();
      return false;
    }
    _incoming[r.deviceId] = r;
    if (_incoming.length > FriendRequestRules.maxEntries) {
      final oldest = _incoming.values.toList()
        ..sort((a, b) => a.atMs.compareTo(b.atMs));
      _incoming.remove(oldest.first.deviceId);
    }
    await _save();
    notifyListeners();
    return true;
  }

  /// Decline: the row goes, the request stays silent until 24 h are over.
  Future<void> decline(String deviceId) async {
    final old = _incoming[deviceId];
    if (old == null) return;
    _incoming[deviceId] = old.copyWith(declined: true);
    await _save();
    notifyListeners();
  }

  Future<void> removeIncoming(String deviceId) async {
    if (_incoming.remove(deviceId) == null) return;
    await _save();
    notifyListeners();
  }

  /// Removes every request from [userId] (block).
  Future<void> removeUser(String userId) async {
    if (userId.isEmpty) return;
    final before = _incoming.length + _sent.length;
    _incoming.removeWhere((_, r) => r.userId == userId);
    _sent.removeWhere((_, v) => v.$1 == userId);
    if (_incoming.length + _sent.length == before) return;
    await _save();
    notifyListeners();
  }

  bool isSent(String deviceId) {
    final v = _sent[deviceId];
    return v != null && FriendRequestRules.alive(v.$2, now());
  }

  bool isSentUser(String userId) {
    if (userId.isEmpty) return false;
    final t = now();
    return _sent.values
        .any((v) => v.$1 == userId && FriendRequestRules.alive(v.$2, t));
  }

  Future<void> markSent(String deviceId, String userId) async {
    if (deviceId.isEmpty) return;
    final old = _sent[deviceId];
    // The 24 h start at the first "wait", not at every repeat.
    if (old != null && FriendRequestRules.alive(old.$2, now())) return;
    _sent[deviceId] = (userId, now());
    await _save();
    notifyListeners();
  }

  /// Clears the "Requested" mark (by phone or person).
  Future<void> clearSent({String deviceId = '', String userId = ''}) async {
    final before = _sent.length;
    _sent.removeWhere((k, v) =>
        (deviceId.isNotEmpty && k == deviceId) ||
        (userId.isNotEmpty && v.$1 == userId));
    if (_sent.length == before) return;
    await _save();
    notifyListeners();
  }
}
