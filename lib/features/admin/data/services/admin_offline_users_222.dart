import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/local_store.dart';

/// Bundle 222 (section 8, mock U-1 / U-2): accounts made offline that the
/// admin phone learned phone to phone (Wi-Fi Direct / mesh / router) and
/// that are not on the server yet. The signed profile card is NOT changed:
/// such a person still has an `offline_…` user id here (a join moves it to
/// the real id, 218), so that is the rule.
class OfflineUser222 {
  final String userId; // offline_…
  final String deviceId;
  final String username;
  final String name;
  final String phoneModel;
  final String link; // Wi-Fi Direct | mesh | router | nearby
  final String seenAt; // RFC 3339 or ''
  final bool carried; // this phone carries her join box (222 section 9)

  const OfflineUser222({
    required this.userId,
    required this.deviceId,
    required this.username,
    required this.name,
    this.phoneModel = '',
    this.link = 'nearby',
    this.seenAt = '',
    this.carried = false,
  });

  /// The same map shape as a server Users row, so search and names work.
  Map<String, dynamic> toRow() => {
        'id': userId,
        'username': username,
        'display_name': name,
        'status': 'not_on_server',
        'devices': deviceId.isEmpty ? 0 : 1,
      };
}

abstract final class AdminOfflineUsers222 {
  static const String cacheKey = 'admin_users_cache_222';
  static const String idMovesKey = 'id_moves_218';
  static const Duration joinedNote = Duration(days: 7);

  /// The offline rows (Admin → Users listens).
  static final ValueNotifier<List<OfflineUser222>> rows = ValueNotifier(const []);

  /// Bundle 238: rows not seen for [hideAfter], or whose phone now has a
  /// server account (a cleared phone that joined again). Only hidden on the
  /// list ("Show hidden (N)"); nothing is deleted.
  static final ValueNotifier<List<OfflineUser222>> hidden = ValueNotifier(const []);
  static const Duration hideAfter = Duration(days: 30);

  /// Bundle 238 (pure, tests): which rows are hidden. [directory] is the
  /// phone's directory (user_id, device_id); a phone that now shows a
  /// non-offline account is a cleared phone, so its old offline row hides.
  static (List<OfflineUser222>, List<OfflineUser222>) split238(
      List<OfflineUser222> all,
      {required List<Map<String, Object?>> directory, DateTime? now}) {
    final t0 = (now ?? DateTime.now()).toUtc();
    final rejoined = <String>{};
    for (final r in directory) {
      final id = '${r['user_id'] ?? ''}';
      final dev = '${r['device_id'] ?? ''}';
      if (id.isNotEmpty && dev.isNotEmpty && !id.startsWith('offline_')) rejoined.add(dev);
    }
    final shown = <OfflineUser222>[];
    final gone = <OfflineUser222>[];
    for (final u in all) {
      final t = DateTime.tryParse(u.seenAt);
      final old = t != null && t0.difference(t.toUtc()) > hideAfter;
      if (old || (u.deviceId.isNotEmpty && rejoined.contains(u.deviceId))) {
        gone.add(u);
      } else {
        shown.add(u);
      }
    }
    return (shown, gone);
  }

  /// Set by AppDependencies; reads the phone's own data.
  static LocalStore? _store;
  static Future<bool> Function(String deviceId)? _carries;

  static void init(LocalStore store, {Future<bool> Function(String deviceId)? carries}) {
    _store = store;
    _carries = carries;
  }

  @visibleForTesting
  static void resetForTest() {
    _store = null;
    _carries = null;
    rows.value = const [];
    hidden.value = const [];
  }

  /// "Wi-Fi Direct" / "mesh" / "router" / "nearby" from the phone's link
  /// flags (same words as the app's map).
  static String linkOf(Device? d) {
    if (d == null) return 'nearby';
    if (d.wifiDirectConnected) return 'Wi-Fi Direct';
    if (d.meshAvailable) return 'mesh';
    if (d.lanAvailable) return 'router';
    return 'nearby';
  }

  /// Pure rule (tests): offline-id people, minus me, minus anyone the
  /// server list has, minus anyone whose id already moved (joined).
  static List<OfflineUser222> pick({
    required List<Map<String, Object?>> directory,
    required List<Device> devices,
    required Set<String> serverIds,
    required Map<String, String> moves,
    required String selfUserId,
    Set<String> carried = const {},
  }) {
    final byId = {for (final d in devices) d.id: d};
    final out = <OfflineUser222>[];
    final seen = <String>{};
    for (final r in directory) {
      final id = '${r['user_id'] ?? ''}';
      if (!id.startsWith('offline_') || id == selfUserId || !seen.add(id)) continue;
      if (serverIds.contains(id) || moves.containsKey(id)) continue;
      final dev = '${r['device_id'] ?? ''}';
      final d = byId[dev];
      final user = '${r['username'] ?? ''}'.trim();
      final name = '${r['display_name'] ?? ''}'.trim();
      var seenAt = d?.lastSeenAt ?? '';
      if (seenAt.isEmpty) seenAt = '${r['synced_at'] ?? ''}';
      out.add(OfflineUser222(
        userId: id,
        deviceId: dev,
        username: user,
        name: name.isNotEmpty ? name : (user.isNotEmpty ? user : 'Offline account'),
        phoneModel: (d?.name ?? '').trim(),
        link: linkOf(d),
        seenAt: seenAt,
        carried: carried.contains(dev),
      ));
    }
    out.sort((a, b) => b.seenAt.compareTo(a.seenAt));
    return out;
  }

  /// For the server (presence `offline_seen`, web Users "Not on server
  /// yet"): people seen in the last [within], at most 20.
  static Future<List<Map<String, Object>>> reportList({Duration within = const Duration(minutes: 15)}) async {
    final s = _store;
    if (s == null) return const [];
    try {
      final directory = await s.offlineDirectoryAccounts222();
      if (directory.isEmpty) return const [];
      final devices = await s.localDevices().catchError((Object _) => <Device>[]);
      final carried = <String>{};
      final carries = _carries;
      final list = pick(
        directory: directory,
        devices: devices,
        serverIds: const {},
        moves: parseMoves(await s.readSetting(idMovesKey)),
        selfUserId: s.accountId ?? '',
      );
      // Bundle 279 (A-1): the same rule as the app's own list (238) - a
      // phone that now has a server card is on the server, so its old
      // offline card is not sent (no "Not on server yet" twin on the web).
      final (shown, _) = split238(list, directory: await _allDirectory238(s));
      final now = DateTime.now().toUtc();
      final out = <Map<String, Object>>[];
      for (final u in shown) {
        final t = DateTime.tryParse(u.seenAt);
        if (t == null || now.difference(t.toUtc()) > within || u.deviceId.isEmpty) continue;
        if (carries != null && await carries(u.deviceId).catchError((Object _) => false)) carried.add(u.deviceId);
        out.add({
          'device_id': u.deviceId,
          'user_id': u.userId,
          'username': u.username,
          'name': u.name,
          'model': u.phoneModel,
          'link': u.link,
          'carrying': carried.contains(u.deviceId),
        });
        if (out.length >= 20) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Bundle 238: every directory row (user id + phone id), to see a phone
  /// that now has a server account. Empty on any error.
  static Future<List<Map<String, Object?>>> _allDirectory238(LocalStore s) async {
    try {
      final rows = await s.directoryProfiles();
      return [
        for (final r in rows) {'user_id': r['user_id'], 'device_id': r['device_id']}
      ];
    } catch (_) {
      return const [];
    }
  }

  static Map<String, String> parseMoves(String? raw) {
    final out = <String, String>{};
    try {
      final list = jsonDecode(raw ?? '[]');
      if (list is List) {
        for (final e in list.whereType<Map>()) {
          final o = '${e['old'] ?? ''}';
          final n = '${e['new'] ?? ''}';
          if (o.isNotEmpty && n.isNotEmpty) out[o] = n;
        }
      }
    } catch (_) {}
    return out;
  }

  /// AdminBloc calls this after a good server Users load.
  static Future<void> serverUsersLoaded(List<Map<String, dynamic>> users) async {
    final s = _store;
    if (s == null) return;
    try {
      await s.writeSetting(
          cacheKey,
          jsonEncode([
            for (final u in users.take(5000)) {'id': '${u['id'] ?? ''}', 'username': '${u['username'] ?? ''}'}
          ]));
    } catch (_) {}
    await refresh(server: true);
  }

  /// Re-reads the phone's data (the rows show; a joined person's id has
  /// moved, so she drops out and her server row shows instead).
  static Future<void> refresh({bool server = false}) async {
    final s = _store;
    if (s == null) return;
    try {
      final directory = await s.offlineDirectoryAccounts222();
      final devices = await s.localDevices().catchError((Object _) => <Device>[]);
      final moves = parseMoves(await s.readSetting(idMovesKey));
      final serverIds = <String>{};
      try {
        final cache = jsonDecode(await s.readSetting(cacheKey) ?? '[]');
        if (cache is List) {
          for (final e in cache.whereType<Map>()) {
            serverIds.add('${e['id'] ?? ''}');
          }
        }
      } catch (_) {}
      final carried = <String>{};
      final carries = _carries;
      if (carries != null) {
        for (final r in directory) {
          final dev = '${r['device_id'] ?? ''}';
          if (dev.isNotEmpty && await carries(dev).catchError((Object _) => false)) carried.add(dev);
        }
      }
      final picked = pick(
        directory: directory,
        devices: devices,
        serverIds: serverIds,
        moves: moves,
        selfUserId: s.accountId ?? '',
        carried: carried,
      );
      // Bundle 238: old rows / cleared phones go under "Show hidden (N)".
      final (shown, gone) = split238(picked, directory: await _allDirectory238(s));
      rows.value = List.unmodifiable(shown);
      hidden.value = List.unmodifiable(gone);
      AppLogger.info('USERS_LOCAL_ROWS',
          detail: 'n=${shown.length} server=${server ? 'on' : 'off'}${gone.isEmpty ? '' : ' hidden=${gone.length}'}');
    } catch (e) {
      AppLogger.warning('USERS_LOCAL_ROWS_FAIL', detail: '$e');
    }
  }
}
