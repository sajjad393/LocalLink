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
class SecurityCode245 extends ChangeNotifier {
  SecurityCode245();
  static final SecurityCode245 instance = SecurityCode245();
  static const String settingKey = 'key_change_245';
  static const int maxPending = 200;

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

  bool get bound => myKey != null && profileFor != null;
  int get pendingCount => _pending.length;

  Future<void> load({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    _write = write;
    _pending.clear();
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
