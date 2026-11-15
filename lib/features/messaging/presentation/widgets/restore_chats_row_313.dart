import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/messaging/data/services/chat_restore_313.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 313 (D5): Settings > Chats > "Get chats back from friends".
class RestoreChatsRow313 extends StatelessWidget {
  const RestoreChatsRow313({super.key, this.restore});

  /// Null = [ChatRestore313.instance] (tests pass their own).
  final ChatRestore313? restore;

  static String subtitle(Restore313Status s) {
    final t = L.t;
    final name = s.peer.isEmpty ? t.aFriend313 : s.peer;
    return switch (s.phase) {
      Restore313Status.waiting => t.waitingFriendsNearby313,
      Restore313Status.getting =>
        s.total > 0 ? t.gettingFrom313(name, s.got, s.total) : t.askingFriend313(name),
      Restore313Status.finished => t.restoreDone313,
      Restore313Status.noneNear => t.noFriendsNearby313,
      _ => t.getChatsBackSub313,
    };
  }

  /// The toast after a friend gave messages back.
  static String doneText(Restore313Done d) {
    final name = d.peer.isEmpty ? L.t.aFriend313 : d.peer;
    return d.count == 1 ? L.t.gotOneMessageBack313(name) : L.t.gotMessagesBack313(d.count, name);
  }

  @override
  Widget build(BuildContext context) {
    final r = restore ?? ChatRestore313.instance;
    if (r == null) {
      return MessengerSettingsRow(
        key: const ValueKey('settings_restore_313'),
        icon: Icons.history_rounded,
        title: L.t.getChatsBack313,
        subtitle: L.t.noFriendsNearby313,
      );
    }
    return ValueListenableBuilder<Restore313Status>(
      valueListenable: r.status,
      builder: (context, s, _) => MessengerSettingsRow(
        key: const ValueKey('settings_restore_313'),
        icon: Icons.history_rounded,
        title: L.t.getChatsBack313,
        subtitle: subtitle(s),
        trailing: s.phase == Restore313Status.getting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: s.phase == Restore313Status.getting
            ? null
            : () async {
                final messenger = ScaffoldMessenger.maybeOf(context);
                final asked = await r.askNearbyFriends();
                if (asked == 0) {
                  LinkToast.maybeOn(messenger, L.t.noFriendsNearby313);
                }
              },
      ),
    );
  }
}
