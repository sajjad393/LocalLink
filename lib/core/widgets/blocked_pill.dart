import 'package:flutter/material.dart';

/// Bundle 196: small shared pieces for blocked / private people
/// (Chats, chat bar, Calls, People, profile, search, Settings).

/// Red "🚫 Blocked" label (every screen).
class BlockedPill extends StatelessWidget {
  const BlockedPill({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 1, 7, 1),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: 11, color: colors.error),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
            'Blocked',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.error,
              letterSpacing: 0,
              height: 1.3,
            ),
          ),
          ),
        ],
      ),
    );
  }
}

/// Grey "🔒 Private" label (People row only: that person made their own
/// profile private).
class PrivatePill extends StatelessWidget {
  const PrivatePill({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 1, 7, 1),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 10, color: colors.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            'Private',
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurfaceVariant,
              letterSpacing: 0,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Grey circle + white initial for a blocked person (no presence badge).
class MutedAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const MutedAvatar({super.key, required this.name, this.radius = 21});

  @override
  Widget build(BuildContext context) {
    final value = name.trim();
    final initial = value.isEmpty ? '?' : value.substring(0, 1).toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.outline,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// "@ali" + Blocked pill (blocked rows on every screen).
class BlockedUserLine extends StatelessWidget {
  final String username;

  const BlockedUserLine({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (username.isNotEmpty) ...[
          Flexible(
            child: Text(
              '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13, color: colors.onSurfaceVariant, letterSpacing: 0),
            ),
          ),
          const SizedBox(width: 6),
        ],
        const BlockedPill(),
      ],
    );
  }
}
