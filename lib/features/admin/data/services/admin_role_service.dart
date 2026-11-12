import 'dart:async';

import 'package:locallink/features/admin/data/services/admin_live_hint_274.dart';
import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/models/admin_badge.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';

/// The server's answer to `POST /api/v1/admin/device-session`.
class AdminRoleAnswer {
  final AdminSession? session;
  final SignedBlob? card;
  final bool notAdmin;

  const AdminRoleAnswer({required this.session, this.card}) : notAdmin = false;
  const AdminRoleAnswer.notAdmin()
      : session = null,
        card = null,
        notAdmin = true;
}

/// Bundle 214: the server call (see `admin_role_server.dart`). Throws
/// [AdminRoleUnavailable] (or any error) when the answer can't be trusted
/// to change anything: no server, network error, 401, 5xx.
abstract class AdminRoleServer {
  Future<AdminRoleAnswer> deviceSession({String token = ''});
}

class AdminRoleUnavailable implements Exception {
  final String reason;
  const AdminRoleUnavailable(this.reason);
  @override
  String toString() => 'AdminRoleUnavailable($reason)';
}

enum AdminRoleResult { admin, notAdmin, keep, skipped }

/// Bundle 214: my own admin role, automatic (no admin login or logout).
///
/// - The web marks a user admin; this phone asks the server for a device
///   admin session and saves it in the same [AdminSessionStore] as before,
///   so the 212 block / 213 version tools and the panel work unchanged.
/// - 200 → admin (session + my card + the 212 offline key).
///   403 `not_admin` → not admin any more (cleared).
///   No server / error / 401 → keep what is saved (offline stays admin).
/// - Runs 6 s after start, on every server connect, every 10 min, at once
///   on the `admin_role_changed` push, after an online sign-in and as the
///   background step `admin_role`.
class AdminRoleService {
  AdminRoleService({
    required this.capability,
    required this.read,
    required this.write,
    required this.accountId,
    required this.signedOut,
    this.server,
    this.setCapable,
    this.offerCard,
    this.afterAdmin,
    this.notify,
    this.messages,
    this.onBadgeChanged,
  });

  static const String notedKey = 'admin_role_noted';
  static const Duration every = Duration(minutes: 10);

  final AdminCapabilityService capability;
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final String Function() accountId;
  final Future<bool> Function() signedOut;
  final AdminRoleServer? server;
  final void Function(bool capable)? setCapable;
  final Future<bool> Function(SignedBlob card)? offerCard;

  /// After a 200: 212 trust key + offline key (and its "key ended" notes).
  final Future<void> Function()? afterAdmin;

  /// One notification ([title], [body]) when my role changes.
  final void Function(String title, String body)? notify;

  /// Server push messages (web socket).
  final Stream<Map<String, dynamic>>? messages;
  final void Function()? onBadgeChanged;

  static AdminRoleService? instance;

  /// The saved admin session (null = not admin). The switch sheet, Settings
  /// and the panel listen to it.
  final ValueNotifier<AdminSession?> current = ValueNotifier<AdminSession?>(null);

  bool _started = false;
  bool _busy = false;
  Timer? _timer;
  StreamSubscription<Map<String, dynamic>>? _sub;

  /// G2 / G3: reads the saved session (no server). A session saved for
  /// another account is cleared; a 211 web sign-in (no account) is
  /// cleared and its token sent to the server later as a sign-out.
  Future<AdminSession?> restore() async {
    final session = await capability.readValidSession();
    final owner = await capability.store.readAccount();
    final me = accountId();
    if (session != null && owner == null) {
      await capability.store.savePendingRevoke(session.token);
      await capability.clear();
      AppLogger.info('ADMIN_ROLE_OLD_SIGNIN_CLEARED');
      return _set(null);
    }
    if (session != null && me.isNotEmpty && owner != me) {
      await capability.clear();
      await write(notedKey, '');
      AppLogger.info('ADMIN_ROLE_OTHER_ACCOUNT_CLEARED');
      return _set(null);
    }
    if (session != null && current.value == null) {
      AppLogger.info('ADMIN_ROLE_KEPT_AFTER_SIGNIN', detail: 'role=${session.role}');
    }
    return _set(session);
  }

  AdminSession? _set(AdminSession? session) {
    current.value = session;
    setCapable?.call(session != null);
    return session;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    instance = this;
    if (!await signedOut()) await restore();
    _timer = Timer.periodic(every, (_) => unawaited(refresh(reason: 'timer')));
    _sub = messages?.listen((m) {
      final type = m['type']?.toString();
      if (type == 'admin_role_changed') unawaited(refresh(reason: 'push'));
      if (type == 'admin_badge_changed') onBadgeChanged?.call();
      AdminLiveHint274.onMessage(m); // Bundle 274 (A-2)
    });
    unawaited(Future<void>.delayed(const Duration(seconds: 6), () async {
      if (_started) await refresh(reason: 'start');
    }).catchError((Object _) {}));
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _sub?.cancel();
    _started = false;
    if (identical(instance, this)) instance = null;
  }

  /// G3 / G4: right after a sign-in. Offline: the saved session is back at
  /// once. Online: ask the server now.
  Future<void> afterSignIn({required bool online}) async {
    await restore();
    if (online) await refresh(reason: 'signin');
  }

  Future<AdminRoleResult> refresh({String reason = 'manual'}) async {
    final s = server;
    if (s == null || accountId().isEmpty || await signedOut()) {
      return AdminRoleResult.skipped;
    }
    if (_busy) return AdminRoleResult.skipped;
    _busy = true;
    try {
      final saved = await restore();
      final AdminRoleAnswer answer;
      try {
        answer = await s.deviceSession(token: saved?.token ?? '');
      } catch (e) {
        AppLogger.info('ADMIN_ROLE_KEEP', detail: 'reason=$reason error=$e');
        return AdminRoleResult.keep;
      }
      if (answer.notAdmin) {
        if (saved != null) AppLogger.info('ADMIN_ROLE_REMOVED', detail: 'reason=$reason');
        await capability.clear();
        _set(null);
        await _note('');
        return AdminRoleResult.notAdmin;
      }
      final session = answer.session!;
      await capability.store.saveAccount(accountId());
      await capability.store.save(session);
      _set(session);
      final card = answer.card;
      if (card != null) {
        try {
          await offerCard?.call(card);
        } catch (_) {}
      }
      AppLogger.info('ADMIN_ROLE_OK',
          detail: 'role=${session.role} reason=$reason same_token=${saved?.token == session.token}');
      await _note(session.role);
      try {
        await afterAdmin?.call();
      } catch (_) {}
      return AdminRoleResult.admin;
    } finally {
      _busy = false;
    }
  }

  /// B3: one notification each time my role changes (also app closed).
  Future<void> _note(String role) async {
    final before = await read(notedKey);
    if (before == role) return;
    await write(notedKey, role);
    if (before == null && role.isEmpty) return; // never was admin
    if (role.isEmpty) {
      notify?.call('You are no longer an admin', 'Admin tools are off on this phone.');
    } else if (before == null || before.isEmpty) {
      notify?.call('You are now an admin 👑',
          'Level: ${AdminBadges.roleLabel(role)} · Tap your photo in Settings to switch.');
    } else {
      notify?.call('Your admin level is now ${AdminBadges.roleLabel(role)}',
          'Tap your photo in Settings to switch.');
    }
  }

  @visibleForTesting
  static void resetForTest() => instance = null;
}
