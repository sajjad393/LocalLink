import 'package:flutter/material.dart';

import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/groups/data/group_receipts.dart';

/// Bundle G5 (mock 19 / 20): "Message info" for my group message.
///
/// * Read by 2 of 3 (blue ✓✓) - who + when.
/// * Delivered to 1 (grey ✓✓) - got it, not read (or read receipts off).
///   With nobody read yet: "Delivered to 2 of 3".
/// * Waiting (clock) - "gets it when Nearby or Online".
/// * A message not sent yet keeps the old "Not sent yet" line.
Future<void> showGroupMessageInfoSheet(
  BuildContext context, {
  required Widget preview,
  required GroupMessageInfo info,
  bool notSentYet = false,
  Color? barrierColor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    barrierColor: barrierColor,
    builder: (sheetContext) => GroupMessageInfoBody(
        preview: preview, info: info, notSentYet: notSentYet),
  );
}

class GroupMessageInfoBody extends StatelessWidget {
  const GroupMessageInfoBody({
    super.key,
    required this.preview,
    required this.info,
    this.notSentYet = false,
  });

  final Widget preview;
  final GroupMessageInfo info;
  final bool notSentYet;

  static const Color _head = Color(0xFF33343A);
  static const Color _soft = Color(0xFF5B5C64);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget head(Key key, Widget icon, String text) => Padding(
          key: key,
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 6),
              Text(text,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: _head)),
            ],
          ),
        );
    Widget row(GroupInfoPerson p, String right) => Padding(
          key: ValueKey('ginfo_row_${p.deviceId}'),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Row(
            children: [
              AccountAvatar(name: p.name, radius: 16, peerId: p.deviceId),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Text(right,
                  style: const TextStyle(fontSize: 12.5, color: _soft)),
            ],
          ),
        );
    final children = <Widget>[];
    if (notSentYet) {
      children.add(Padding(
        key: const ValueKey('info_not_sent'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 14),
            const Text('Not sent yet',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ));
    } else {
      if (info.read.isNotEmpty) {
        children.add(head(
            const ValueKey('ginfo_read'),
            Icon(Icons.done_all_rounded, size: 15, color: colors.primary),
            'Read by ${info.read.length} of ${info.total}'));
        for (final p in info.read) {
          children.add(row(p, p.at == null ? '' : messageInfoTime(p.at!)));
        }
      }
      if (info.delivered.isNotEmpty) {
        children.add(head(
            const ValueKey('ginfo_delivered'),
            const Icon(Icons.done_all_rounded, size: 15, color: _soft),
            info.read.isEmpty
                ? 'Delivered to ${info.delivered.length} of ${info.total}'
                : 'Delivered to ${info.delivered.length}'));
        for (final p in info.delivered) {
          children.add(row(p, p.at == null ? '' : messageInfoTime(p.at!)));
        }
      }
      if (info.waiting.isNotEmpty) {
        children.add(head(
            const ValueKey('ginfo_waiting'),
            const Icon(Icons.schedule_rounded, size: 14, color: Color(0xFF6A6B73)),
            'Waiting'));
        for (final p in info.waiting) {
          children.add(row(p, 'gets it when Nearby or Online'));
        }
      }
      children.add(Padding(
        key: const ValueKey('ginfo_hint'),
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          info.waiting.isNotEmpty
              ? '✓ = sent. ✓✓ only when all members got it.'
              : 'Blue ✓✓ in the chat only when all ${info.total} have read it. '
                  'People with read receipts off show under Delivered.',
          style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
        ),
      ));
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('Message info',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontSize: 19, fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(alignment: Alignment.centerRight, child: preview),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
