import 'package:flutter/material.dart';

import 'package:locallink/core/models/message_reaction.dart';

/// Bundle 207: what a tap on an emoji chip under a message does.
/// One reaction per person (as before):
/// * I have not reacted -> add this emoji (count +1);
/// * I reacted this same emoji -> remove mine (count -1), like WhatsApp;
/// * I reacted another emoji -> mine changes to this one.
enum ReactionTapKind { add, remove, change }

ReactionTapKind reactionTapKind(
    List<MessageReaction> reactions, String myId, String emoji) {
  for (final r in reactions) {
    if (myId.isNotEmpty && r.reactorId == myId && r.emoji.isNotEmpty) {
      return r.emoji == emoji ? ReactionTapKind.remove : ReactionTapKind.change;
    }
  }
  return ReactionTapKind.add;
}

/// One chip per emoji ("❤️ 2"), in the order they first appeared. My own
/// emoji gets a light blue border. [onTap] adds / removes mine; [onLongPress]
/// (groups) shows who reacted.
List<Widget> reactionChips(
  BuildContext context, {
  required List<MessageReaction> reactions,
  required String myId,
  required String keyPrefix,
  ValueChanged<String>? onTap,
  ValueChanged<String>? onLongPress,
}) {
  final counts = <String, int>{};
  String? mine;
  for (final r in reactions) {
    if (r.emoji.isEmpty) continue;
    counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    if (myId.isNotEmpty && r.reactorId == myId) mine = r.emoji;
  }
  return counts.entries
      .map((e) => ReactionChip(
            key: ValueKey('${keyPrefix}_${e.key}'),
            emoji: e.key,
            count: e.value,
            mine: e.key == mine,
            onTap: onTap == null ? null : () => onTap(e.key),
            onLongPress: onLongPress == null ? null : () => onLongPress(e.key),
          ))
      .toList(growable: false);
}

class ReactionChip extends StatelessWidget {
  const ReactionChip({
    super.key,
    required this.emoji,
    required this.count,
    this.mine = false,
    this.onTap,
    this.onLongPress,
  });

  final String emoji;
  final int count;
  final bool mine;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: mine ? scheme.primary.withValues(alpha: 0.10) : scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: mine
              ? scheme.primary.withValues(alpha: 0.55)
              : scheme.outlineVariant,
          width: mine ? 1.4 : 1,
        ),
      ),
      child:
          Text('$emoji $count', style: Theme.of(context).textTheme.labelSmall),
    );
    if (onTap == null && onLongPress == null) return chip;
    return Semantics(
      button: true,
      label: mine ? 'Remove your $emoji' : 'React $emoji',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: chip,
      ),
    );
  }
}
