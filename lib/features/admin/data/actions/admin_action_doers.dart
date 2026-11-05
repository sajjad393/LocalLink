import 'package:flutter/foundation.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';

/// Bundle 220: what the target phone does for each action. Built in
/// app_dependencies from the existing services (212 blocks, 214 badges,
/// 213 version rules, Wi-Fi rule, sign out), so no old file changes.
///
/// Each returns the receipt result: `ok`, `already` or `refused:<why>`.
class AdminActionDoers {
  const AdminActionDoers({
    required this.block,
    required this.setClosed,
    required this.wifi,
    required this.badge,
    required this.versionRule,
    required this.signOut,
  });

  /// A 212 block / unblock card (`inner`). True when it was new here.
  final Future<bool> Function(SignedBlob inner) block;

  /// Off (closed) / Active: the `admin_closed_v1` flag.
  final Future<void> Function(bool closed) setClosed;

  /// Wi-Fi rule for this phone (`{wifi_radio_policy: forced_on|forced_off|null}`).
  final Future<void> Function(Map<String, dynamic> policy) wifi;

  /// 214 crown card. True when it was new here.
  final Future<bool> Function(SignedBlob inner) badge;

  /// 213 version rule. True when it was new here.
  final Future<bool> Function(SignedBlob inner) versionRule;

  /// Sign this phone out (removed = also show "removed by admin").
  final Future<void> Function({required bool removed}) signOut;

  static const String closedKey = 'admin_closed_v1';
  static const String removedKey = 'admin_removed_v1';
}

/// Set by the app (local_link_app) so an admin sign-out leaves the chats
/// at once (same path as the Profile "Sign out" button).
abstract final class AdminActionSignOut {
  static Future<void> Function()? onSignedOut;
}

/// Bundle 220 (Q2): this account was closed (Off) by an admin. The blocked
/// banner then says "Account closed by admin".
abstract final class AdminClosedFlag {
  static final ValueNotifier<bool> closed = ValueNotifier<bool>(false);
}
