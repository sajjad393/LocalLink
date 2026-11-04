import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_bubble.dart';

/// Bundle G5 (mock 16): one row of the "@" list.
class GroupMentionChoice {
  const GroupMentionChoice({
    required this.id,
    required this.name,
    required this.sub,
    this.everyone = false,
  });

  final String id;
  final String name;
  final String sub;

  /// The "@all" row (group photo, admins only).
  final bool everyone;
}

/// Bundle G5 (mock 16): the white card over the message box - member rows
/// (photo, name, role) and, for admins, "@all · Admins only: notify
/// everyone".
class GroupMentionList extends StatelessWidget {
  const GroupMentionList({super.key, required this.choices, required this.onPick});

  final List<GroupMentionChoice> choices;
  final ValueChanged<GroupMentionChoice> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('group_mention_list'),
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Material(
        color: colors.surface,
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x2E000000), blurRadius: 16, offset: Offset(0, 4)),
            ],
            color: colors.surface,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: choices.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEF3)),
              itemBuilder: (context, i) {
                final c = choices[i];
                return InkWell(
                  key: ValueKey('mention_${c.id}'),
                  onTap: () => onPick(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      children: [
                        if (c.everyone)
                          Container(
                            width: 34,
                            height: 34,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LocalLinkBrand.heroGradient),
                            child: const Icon(Icons.groups_rounded,
                                size: 20, color: Colors.white),
                          )
                        else
                          AccountAvatar(name: c.name, radius: 17, peerId: c.id),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(c.everyone ? '@all' : c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14.5, fontWeight: FontWeight.w600)),
                              Text(c.sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5, color: Color(0xFF5B5C64))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Bundle G5 (mock 15): the typer's photo, coloured name and three dots.
class GroupTypingBubble extends StatefulWidget {
  const GroupTypingBubble({super.key, required this.name, required this.deviceId});

  final String name;
  final String deviceId;

  @override
  State<GroupTypingBubble> createState() => _GroupTypingBubbleState();
}

class _GroupTypingBubbleState extends State<GroupTypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dots = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: LocalLinkSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: GroupMessageBubble.avatarSlot,
            child: Align(
                alignment: Alignment.topLeft,
                child: AccountAvatar(name: widget.name, radius: 14, peerId: widget.deviceId)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(LocalLinkRadius.chat),
                topRight: Radius.circular(LocalLinkRadius.chat),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(LocalLinkRadius.chat),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.name,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: GroupMessageBubble.nameColor(widget.name))),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
                  child: AnimatedBuilder(
                    animation: _dots,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Opacity(
                            opacity: _dotOpacity(_dots.value, i),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                  color: Color(0xFF8D8E96), shape: BoxShape.circle),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Each dot fades in turn (0.2 s apart), like the mock.
  static double _dotOpacity(double t, int i) {
    final phase = (t - i * (0.2 / 1.2)) % 1.0;
    final wave = phase < .5 ? phase * 2 : (1 - phase) * 2;
    return .35 + .65 * wave;
  }
}
