// Bundle 210: the two ways into Share LinkUp - the Settings row and the
// People card "Invite a friend nearby". Both open [ShareAppScreen].

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/share_app/presentation/share_app_screen.dart';

void openShareApp(BuildContext context, {required String ownerName}) {
  Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => ShareAppScreen(ownerName: ownerName),
  ));
}

/// "NEW" for 14 days after the first time it is shown.
abstract final class ShareAppNewBadge {
  static const String key = 'share_app_new_seen_at';
  static const Duration showFor = Duration(days: 14);
  static Future<bool>? _cached;

  static Future<bool> isNew({DateTime? now}) =>
      _cached ??= _read(now ?? DateTime.now());

  static Future<bool> _read(DateTime now) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getInt(key);
      if (seen == null) {
        await prefs.setInt(key, now.millisecondsSinceEpoch);
        return true;
      }
      return now.millisecondsSinceEpoch - seen < showFor.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void resetForTest() => _cached = null;
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: ShareAppNewBadge.isNew(),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Container(
          key: const ValueKey('share_new_badge'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF0BB5AC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text('NEW',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}

/// Settings → "This phone" → Share LinkUp.
class ShareAppSettingsRow extends StatelessWidget {
  final String ownerName;
  const ShareAppSettingsRow({super.key, required this.ownerName});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MessengerSettingsRow(
      key: const ValueKey('settings_share_app'),
      icon: Icons.ios_share_rounded,
      title: 'Share LinkUp',
      subtitle: 'Give the app to a nearby phone · no internet',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        const _NewBadge(),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right, color: colors.onSurfaceVariant, size: 20),
      ]),
      onTap: () => openShareApp(context, ownerName: ownerName),
    );
  }
}

/// People tab: the card under the search box.
class InviteNearbyCard extends StatelessWidget {
  final String ownerName;
  const InviteNearbyCard({super.key, required this.ownerName});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const ValueKey('people_invite_nearby'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => openShareApp(context, ownerName: ownerName),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colors.primary,
                child: Icon(Icons.ios_share_rounded,
                    size: 18, color: colors.onPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Invite a friend nearby',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('Give them LinkUp · no internet',
                        style: TextStyle(
                            fontSize: 12, color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              const _NewBadge(),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}
