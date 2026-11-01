import 'package:flutter/material.dart';

import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/directory/presentation/contact_sheets.dart';

/// Bundle 196 (11.5, mock 8): Settings › PRIVACY › Blocked people.
/// Rows: muted avatar, name, @user + Blocked pill, outlined "Unblock".
/// Tap a row (or Unblock) = the Unblock sheet (and add back / only).
class BlockedPeopleScreen extends StatelessWidget {
  const BlockedPeopleScreen({super.key});

  static String countLabel(int n) => n == 1 ? '1 person' : '$n people';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked people')),
      body: ListenableBuilder(
        listenable: BlockHub.instance,
        builder: (context, _) {
          final people = BlockHub.instance.people;
          if (people.isEmpty) {
            return Center(
              key: const ValueKey('blocked_people_empty'),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  "You haven't blocked anyone.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView(
            key: const ValueKey('blocked_people_list'),
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              MessengerGroupLabel(countLabel(people.length), top: 12),
              MessengerListGroup(children: [
                for (final p in people)
                  ListTile(
                    key: ValueKey('blocked_people_row_${p.userId}'),
                    leading: MutedAvatar(name: p.label, radius: 24),
                    title: Text(
                      p.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    subtitle: Align(
                      alignment: Alignment.centerLeft,
                      child: BlockedUserLine(username: p.username),
                    ),
                    trailing: OutlinedButton(
                      key: ValueKey('blocked_people_unblock_${p.userId}'),
                      onPressed: () =>
                          runUnblockFlow(context, p, from: 'settings'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: colors.outline),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Unblock'),
                    ),
                    onTap: () => runUnblockFlow(context, p, from: 'settings'),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  'Tap a person to see more.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5, color: colors.onSurfaceVariant),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
