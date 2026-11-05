import 'package:flutter/foundation.dart';
import 'package:locallink/features/admin/data/actions/admin_action_card.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/delete_completely_doer.dart';
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
    this.chat221,
  });

  /// Bundle 221: get_chat / get_file / delete_completely ([ChatDoer221]).
  final Future<String> Function(AdminActionCard card, AdminActionPlain plain)? chat221;

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

/// Bundle 221: the 3 new actions on the target phone. Throws (= no receipt
/// yet, tried again later) when this phone has no copy of the chat / file,
/// so a phone without it never ends the request with an empty answer.
class ChatDoer221 {
  ChatDoer221({required this.builder, required this.carrier, required this.purge});

  final ChatAnswerBuilder builder;
  final ChatAnswerCarrier carrier;
  final DeleteCompletelyDoer purge;

  /// Who the answer is for: `server` (web) or the admin phone (offline card).
  static String replyToOf(AdminActionCard card) {
    if (card.signer != 'admin') return 'server';
    final cert = card.cert == null ? null : AdminCert.fromBlob(card.cert!);
    return cert?.deviceId ?? '';
  }

  Future<String> call(AdminActionCard card, AdminActionPlain plain) async {
    switch (card.action) {
      case 'get_chat':
      case 'get_file':
        final replyTo = replyToOf(card);
        if (card.replyKey.isEmpty || replyTo.isEmpty) return 'refused:no_reply_key';
        final file = card.action == 'get_file';
        List<ChatAnswerPart> parts;
        try {
          parts = file
              ? await builder.buildFile(
                  actionId: card.id, replyKey: card.replyKey, replyTo: replyTo, detail: plain.detail)
              : await builder.buildChat(
                  actionId: card.id, replyKey: card.replyKey, replyTo: replyTo, detail: plain.detail);
        } on StateError catch (e) {
          final why = e.message;
          if (why == 'no_copy_here' || why == 'no_file') rethrow; // another phone answers
          return 'refused:$why';
        }
        await carrier.addOwn(parts, replyTo: replyTo, isFile: file);
        return 'ok';
      case 'delete_completely':
        await purge.run(plain.detail);
        return 'ok';
    }
    return 'refused:unknown';
  }
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
