import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/security/identity_trust_service.dart';
import 'package:locallink/core/security/safety_number.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/link_key_refresh_257.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';

/// Bundle 245 (audit S7): Security code + key-change warning.
///
/// * [view] gives the 12 x 5 digit code of a chat (my signing key + the
///   friend's card key) and its state (Not verified / Verified / Changed).
/// * A friend's card with a DIFFERENT signing key used to be dropped with no
///   word (a reinstalled friend could never be updated, X4). Now the checked
///   new card is kept aside ([noteCardChange]); the chat shows
///   "<name>'s security code changed" and the Security code screen has
///   "Accept new code". Nothing is taken automatically.
/// * Only for contacts. A friend I had marked Verified becomes "changed"
///   ([IdentityTrustService.markChanged]) so calls show the existing
///   warning; everyone else works as before until they tap Accept.
/// Kept in settings `key_change_245` (no database change).
///
/// Bundle 258 (A): a new code is now taken BY ITSELF when it is proven -
/// the card came from that phone itself, or the server says that phone has
/// that key ([autoTake258]). The chat shows a grey line "Security code
/// changed" for 24 h (no button); a Verified friend goes back to Not
/// verified. Only a card nobody could prove (passed on by someone else,
/// server not reachable) still waits here, and is taken as soon as one of
/// the proofs comes. Auto changes are kept in settings `key_auto_258`.
class SecurityCode245 extends ChangeNotifier {
  SecurityCode245();
  static final SecurityCode245 instance = SecurityCode245();
  static const String settingKey = 'key_change_245';
  static const int maxPending = 200;
  static const String autoSettingKey = 'key_auto_258';
  static const Duration autoShowFor = Duration(hours: 24);

  // Bindings (AppDependencies). Null in tests that don't bind = feature off.
  Future<String> Function()? myKey;
  String Function()? myUserId;
  Future<Map<String, dynamic>?> Function(String id)? profileFor; // device or user id
  Future<void> Function(Map<String, dynamic> profile)? saveProfile;
  Future<bool> Function(DirectoryProfile profile)? verifyProfile;
  Future<bool> Function(String userId)? isContact;
  Future<IdentityTrustState> Function(String deviceId)? trustState;
  Future<void> Function(String deviceId)? markVerified;
  Future<void> Function(String deviceId)? markChanged;
  Future<void> Function(String deviceId)? clearTrust;

  Future<void> Function(String key, String value)? _write;
  final Map<String, PendingKey245> _pending = <String, PendingKey245>{};
  final Map<String, AutoKey258> _auto = <String, AutoKey258>{};

  bool get bound => myKey != null && profileFor != null;
  int get pendingCount => _pending.length;

  Future<void> load({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    _write = write;
    _pending.clear();
    _auto.clear();
    try {
      final raw = await read(autoSettingKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) {
          for (final e in map.entries) {
            final a = AutoKey258.fromJson(e.value);
            if (a != null) _auto[e.key.toString()] = a;
          }
        }
      }
    } catch (_) {}
    try {
      final raw = await read(settingKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) {
          for (final e in map.entries) {
            final p = PendingKey245.fromJson(e.value);
            if (p != null) _pending[e.key.toString()] = p;
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    final w = _write;
    if (w == null) return;
    try {
      await w(settingKey, jsonEncode({for (final e in _pending.entries) e.key: e.value.toJson()}));
    } catch (_) {}
  }

  Future<void> _saveAuto() async {
    final w = _write;
    if (w == null) return;
    final now = DateTime.now().toUtc();
    _auto.removeWhere((_, a) => now.difference(a.at) > autoShowFor);
    try {
      await w(autoSettingKey,
          jsonEncode({for (final e in _auto.entries) e.key: e.value.toJson()}));
    } catch (_) {}
  }

  /// Bundle 258 (A1): the new card was proven ([why] = owner / server) and
  /// is saved by the caller. No waiting change any more; a Verified friend
  /// goes back to Not verified (no call warning); the chat shows the grey
  /// line. Never throws.
  Future<void> autoTake258(
      DirectoryProfile old, DirectoryProfile incoming, String why) async {
    try {
      final user = incoming.userId;
      if (user.isEmpty) return;
      final hadPending = _pending.remove(user) != null;
      if (hadPending) await _save();
      final trust = trustState;
      for (final id in {old.deviceId, incoming.deviceId}) {
        if (id.isEmpty) continue;
        final state =
            trust == null ? null : await trust(id);
        if (state == IdentityTrustState.verified ||
            state == IdentityTrustState.changed) {
          await clearTrust?.call(id);
        }
      }
      _auto[user] = AutoKey258(
          oldDeviceId: old.deviceId,
          deviceId: incoming.deviceId,
          at: DateTime.now().toUtc());
      await _saveAuto();
      AppLogger.info('KEY_AUTO_258',
          detail: 'user=${_tail(user)} phone=${_tail(incoming.deviceId)} '
              'why=$why${hadPending ? ' was_waiting=y' : ''}');
      LinkKeyRefresh257.request('key_auto');
      notifyListeners();
    } catch (_) {}
  }

  /// Bundle 258 (A2): a change taken by itself in the last 24 h for this
  /// chat (by its phone id: the old or the new), and not seen yet.
  AutoKey258? autoFor(String deviceId, {String userId = ''}) {
    final now = DateTime.now().toUtc();
    bool fresh(AutoKey258 a) => !a.seen && now.difference(a.at) <= autoShowFor;
    final byUser = userId.isEmpty ? null : _auto[userId];
    if (byUser != null) return fresh(byUser) ? byUser : null;
    for (final a in _auto.values) {
      if ((a.oldDeviceId == deviceId || a.deviceId == deviceId) && fresh(a)) {
        return a;
      }
    }
    return null;
  }

  /// Bundle 258 (A2): the Security code screen was opened - the grey line
  /// goes away for that chat.
  Future<void> autoSeen258(String deviceId) async {
    var changed = false;
    for (final e in _auto.entries.toList()) {
      final a = e.value;
      if (!a.seen && (a.oldDeviceId == deviceId || a.deviceId == deviceId)) {
        _auto[e.key] = a.markSeen();
        changed = true;
      }
    }
    if (!changed) return;
    await _saveAuto();
    notifyListeners();
  }

  /// Bundle 258 (A3): the cards still waiting (older builds, or no proof
  /// yet), to be checked again.
  List<PendingKey245> get pendingCards => List.unmodifiable(_pending.values);

  /// A checked card whose signing key differs from the one I keep.
  /// Never throws.
  Future<void> noteCardChange(DirectoryProfile old, DirectoryProfile incoming) async {
    try {
      final user = incoming.userId;
      if (user.isEmpty || incoming.signingPublicKey.isEmpty) return;
      final contact = isContact;
      if (contact != null && !await contact(user)) return;
      final had = _pending[user];
      if (had != null &&
          had.profile.signingPublicKey == incoming.signingPublicKey &&
          had.profile.profileVersion >= incoming.profileVersion) {
        return; // the same change again
      }
      _pending[user] = PendingKey245(
          profile: incoming, oldDeviceId: old.deviceId, at: DateTime.now().toUtc());
      while (_pending.length > maxPending) {
        final oldest = _pending.entries.reduce((a, b) => a.value.at.isBefore(b.value.at) ? a : b);
        _pending.remove(oldest.key);
      }
      final trust = trustState;
      if (trust != null && await trust(old.deviceId) == IdentityTrustState.verified) {
        await markChanged?.call(old.deviceId);
      }
      await _save();
      AppLogger.warning('KEY_CHANGE_245',
          detail: 'user=${_tail(user)} old_phone=${_tail(old.deviceId)} new_phone=${_tail(incoming.deviceId)}');
      notifyListeners();
    } catch (_) {}
  }

  /// The waiting change for a chat (by its phone id: the old or the new).
  PendingKey245? pendingFor(String deviceId, {String userId = ''}) {
    if (userId.isNotEmpty && _pending[userId] != null) return _pending[userId];
    for (final p in _pending.values) {
      if (p.oldDeviceId == deviceId || p.profile.deviceId == deviceId) return p;
    }
    return null;
  }

  Future<SecurityCodeView245?> view(String deviceId) async {
    final mine = myKey, me = myUserId, find = profileFor;
    if (mine == null || me == null || find == null) return null;
    final row = await find(deviceId);
    if (row == null) return null;
    final friend = DirectoryProfile.fromMap(row);
    final myK = await mine();
    if (friend.signingPublicKey.isEmpty || myK.isEmpty) return null;
    final digits = await digitsRunner([me(), myK, friend.userId, friend.signingPublicKey]);
    final state = await trustState?.call(friend.deviceId) ?? IdentityTrustState.unverified;
    return SecurityCodeView245(
      userId: friend.userId,
      deviceId: friend.deviceId,
      digits: digits,
      state: state,
      pending: pendingFor(friend.deviceId, userId: friend.userId),
    );
  }

  static String _digits(List<String> a) => SafetyNumber.of(a[0], a[1], a[2], a[3]);

  /// 10 400 SHA-512 rounds: off the UI thread. Tests may run it inline.
  static Future<String> Function(List<String> args) digitsRunner =
      (a) => compute(_digits, a);
  static String digitsNow(List<String> a) => _digits(a);

  Future<void> setVerified(String deviceId, bool verified) async {
    if (verified) {
      await markVerified?.call(deviceId);
    } else {
      await clearTrust?.call(deviceId);
    }
    AppLogger.info('SECURITY_CODE_245', detail: 'verified=${verified ? 'y' : 'n'} phone=${_tail(deviceId)}');
    notifyListeners();
  }

  /// "Accept new code": the kept card is checked again and saved. The trust
  /// state goes back to Not verified (compare the new code to verify).
  Future<bool> accept(String userId) async {
    final p = _pending[userId];
    final save = saveProfile;
    if (p == null || save == null) return false;
    final check = verifyProfile;
    if (check != null && !await check(p.profile)) {
      AppLogger.warning('KEY_ACCEPT_245', detail: 'result=bad_signature user=${_tail(userId)}');
      return false;
    }
    await save(p.profile.toMap());
    await clearTrust?.call(p.oldDeviceId);
    if (p.profile.deviceId != p.oldDeviceId) await clearTrust?.call(p.profile.deviceId);
    _pending.remove(userId);
    await _save();
    AppLogger.info('KEY_ACCEPT_245', detail: 'result=saved user=${_tail(userId)}');
    LinkKeyRefresh257.request('accept'); // Bundle 257 (A3/A6)
    notifyListeners();
    return true;
  }

  static String _tail(String v) => v.length <= 6 ? v : v.substring(v.length - 6);

  @visibleForTesting
  void resetForTest() {
    _pending.clear();
    _auto.clear();
    myKey = null;
    myUserId = null;
    profileFor = null;
    saveProfile = null;
    verifyProfile = null;
    isContact = null;
    trustState = null;
    markVerified = null;
    markChanged = null;
    clearTrust = null;
    _write = null;
  }
}

class PendingKey245 {
  const PendingKey245({required this.profile, required this.oldDeviceId, required this.at});
  final DirectoryProfile profile;
  final String oldDeviceId;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'profile': profile.toMap(),
        'old_device_id': oldDeviceId,
        'at': at.toIso8601String(),
      };

  static PendingKey245? fromJson(Object? v) {
    if (v is! Map) return null;
    try {
      final p = v['profile'];
      if (p is! Map) return null;
      final profile = DirectoryProfile.fromMap(Map<String, dynamic>.from(p));
      if (profile.userId.isEmpty || profile.signingPublicKey.isEmpty) return null;
      return PendingKey245(
        profile: profile,
        oldDeviceId: v['old_device_id']?.toString() ?? '',
        at: DateTime.tryParse(v['at']?.toString() ?? '') ?? DateTime.now().toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}

class SecurityCodeView245 {
  const SecurityCodeView245({
    required this.userId,
    required this.deviceId,
    required this.digits,
    required this.state,
    this.pending,
  });
  final String userId;
  final String deviceId;
  final String digits;
  final IdentityTrustState state;
  final PendingKey245? pending;

  List<String> get groups => SafetyNumber.groups(digits);
}

/// Bundle 258 (A2): a code that changed by itself (for the grey line).
class AutoKey258 {
  const AutoKey258({
    required this.oldDeviceId,
    required this.deviceId,
    required this.at,
    this.seen = false,
  });
  final String oldDeviceId;
  final String deviceId;
  final DateTime at;
  final bool seen;

  AutoKey258 markSeen() =>
      AutoKey258(oldDeviceId: oldDeviceId, deviceId: deviceId, at: at, seen: true);

  Map<String, dynamic> toJson() => {
        'old_device_id': oldDeviceId,
        'device_id': deviceId,
        'at': at.toIso8601String(),
        if (seen) 'seen': true,
      };

  static AutoKey258? fromJson(Object? v) {
    if (v is! Map) return null;
    final at = DateTime.tryParse(v['at']?.toString() ?? '');
    if (at == null) return null;
    return AutoKey258(
      oldDeviceId: v['old_device_id']?.toString() ?? '',
      deviceId: v['device_id']?.toString() ?? '',
      at: at,
      seen: v['seen'] == true,
    );
  }
}
