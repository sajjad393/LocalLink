import 'package:flutter/material.dart';

import 'package:locallink/core/models/message_envelope.dart';

/// Bundle 197a (mock v8): the shared message-option sheets and small
/// widgets used by the 1-to-1 chat and the group chat.

const List<String> kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Purple quote line for "You", blue for the friend (TODO 2.5 R3).
const Color kQuoteYouColor = Color(0xFF7C3AED);

enum MessageAction {
  react,
  reply,
  copy,
  forward,
  save,
  info,
  select,
  delete,
  // Bundle G5b (mock P1/P4): groups only (admins).
  pin,
  unpin,
}

/// Bundle G5b: the pin row of the hold sheet (groups, admins only).
enum PinRow { none, pin, unpin }

class MessageActionResult {
  final MessageAction action;
  final String? emoji;
  const MessageActionResult(this.action, [this.emoji]);
}

/// Hold a message (mock 2, 3, 20): emoji row, Reply, Copy, Forward,
/// Message info (own only), Select, Delete (red).
Future<MessageActionResult?> showMessageActionsSheet(
  BuildContext context, {
  required bool mine,
  required bool hasText,
  bool canReply = true,
  bool canForward = true,
  bool canReact = true,
  bool canSave = false,
  Color? barrierColor,
  PinRow pinRow = PinRow.none,
}) {
  return showModalBottomSheet<MessageActionResult>(
    context: context,
    showDragHandle: true,
    barrierColor: barrierColor,
    builder: (sheetContext) {
      final colors = Theme.of(sheetContext).colorScheme;
      Widget row(MessageAction action, IconData icon, String label,
          {bool danger = false}) {
        final color = danger ? colors.error : colors.onSurface;
        return ListTile(
          key: ValueKey('msg_action_${action.name}'),
          leading: Icon(icon, color: danger ? colors.error : colors.onSurfaceVariant),
          title: Text(label,
              style: TextStyle(
                  color: color, fontSize: 15.5, fontWeight: FontWeight.w500)),
          onTap: () => Navigator.pop(sheetContext, MessageActionResult(action)),
        );
      }

      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canReact) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final emoji in kQuickReactions)
                        IconButton(
                          tooltip: 'React $emoji',
                          onPressed: () => Navigator.pop(sheetContext,
                              MessageActionResult(MessageAction.react, emoji)),
                          icon: Text(emoji, style: const TextStyle(fontSize: 28)),
                        ),
                    ],
                  ),
                  const Divider(height: 12),
                ],
                if (canReply) row(MessageAction.reply, Icons.reply_rounded, 'Reply'),
                if (hasText) row(MessageAction.copy, Icons.copy_outlined, 'Copy'),
                if (canForward)
                  row(MessageAction.forward, Icons.forward_rounded, 'Forward'),
                // Bundle 197b (P1): received media, Android 10+.
                if (canSave && !mine)
                  row(MessageAction.save, Icons.download_rounded, 'Save to phone'),
                if (mine)
                  row(MessageAction.info, Icons.info_outline_rounded, 'Message info'),
                // Bundle G5b (mock P1 / P4).
                if (pinRow == PinRow.pin)
                  row(MessageAction.pin, Icons.push_pin_outlined, 'Pin'),
                if (pinRow == PinRow.unpin)
                  ListTile(
                    key: const ValueKey('msg_action_unpin'),
                    leading: SizedBox(
                      width: 24,
                      height: 24,
                      child: Stack(alignment: Alignment.center, children: [
                        Icon(Icons.push_pin_outlined,
                            color: colors.onSurfaceVariant),
                        Transform.rotate(
                          angle: -.785,
                          child: Container(
                              width: 2.2,
                              height: 26,
                              color: colors.onSurfaceVariant),
                        ),
                      ]),
                    ),
                    title: Text('Unpin',
                        style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500)),
                    onTap: () => Navigator.pop(
                        sheetContext, const MessageActionResult(MessageAction.unpin)),
                  ),
                row(MessageAction.select, Icons.check_circle_outline_rounded, 'Select'),
                row(MessageAction.delete, Icons.delete_outline_rounded, 'Delete',
                    danger: true),
              ],
            ),
          ),
        ),
      );
    },
  );
}

enum DeleteChoice { forMe, forEveryone }

/// "Delete message?" / "Delete 3 messages?" (mock 5, 6, 14).
Future<DeleteChoice?> showDeleteMessagesSheet(
  BuildContext context, {
  required int count,
  required bool allowEveryone,
  required String peerName,
  Widget? preview,
  bool group = false,
  Color? barrierColor,
}) {
  return showModalBottomSheet<DeleteChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    barrierColor: barrierColor,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = theme.colorScheme;
      final who = group ? 'the group' : peerName;
      final hint = allowEveryone
          ? (count == 1
              ? '"Delete for everyone" removes it from $who${group ? '' : "'s phone"} too, '
                  'even if ${group ? 'someone is' : 'he is'} Offline now (it is removed when '
                  'the phone gets the news). Only for your messages, up to 5 minutes old. '
                  'A copy someone saved to the Gallery stays.'
              : 'All $count are yours and less than 5 minutes old, so '
                  '"Delete for everyone" is shown. A copy someone saved to the Gallery stays.')
          : (group
              ? 'It is removed only from your phone. The group still has it.'
              : 'It is removed only from your phone. $peerName still has it.');
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(count == 1 ? 'Delete message?' : 'Delete $count messages?',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontSize: 19, fontWeight: FontWeight.w700)),
              if (preview != null) ...[
                const SizedBox(height: 12),
                preview,
              ],
              const SizedBox(height: 10),
              Text(hint,
                  key: const ValueKey('delete_sheet_hint'),
                  style: TextStyle(
                      fontSize: 13, height: 1.35, color: colors.onSurfaceVariant)),
              const SizedBox(height: 12),
              if (allowEveryone) ...[
                _wideButton(
                  key: const ValueKey('delete_for_everyone'),
                  label: 'Delete for everyone',
                  filled: true,
                  colors: colors,
                  onTap: () =>
                      Navigator.pop(sheetContext, DeleteChoice.forEveryone),
                ),
                const SizedBox(height: 10),
                _wideButton(
                  key: const ValueKey('delete_for_me'),
                  label: 'Delete for me',
                  filled: false,
                  colors: colors,
                  onTap: () => Navigator.pop(sheetContext, DeleteChoice.forMe),
                ),
              ] else
                _wideButton(
                  key: const ValueKey('delete_for_me'),
                  label: 'Delete for me',
                  filled: true,
                  colors: colors,
                  onTap: () => Navigator.pop(sheetContext, DeleteChoice.forMe),
                ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _wideButton({
  required Key key,
  required String label,
  required bool filled,
  required ColorScheme colors,
  required VoidCallback onTap,
}) {
  const shape = StadiumBorder();
  const size = Size.fromHeight(46);
  final style = TextStyle(fontWeight: FontWeight.w700, fontSize: 15);
  return filled
      ? FilledButton(
          key: key,
          onPressed: onTap,
          style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
              minimumSize: size,
              shape: shape),
          child: Text(label, style: style),
        )
      : OutlinedButton(
          key: key,
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error),
              minimumSize: size,
              shape: shape),
          child: Text(label, style: style),
        );
}

/// Message info (mock 4, 21).
Future<void> showMessageInfoSheet(
  BuildContext context, {
  required Widget preview,
  required DateTime sentAt,
  DateTime? deliveredAt,
  bool group = false,
  bool notSentYet = false,
  String peerName = '',
  Color? barrierColor,
  // Bundle 198: read receipts (1-to-1 only).
  DateTime? readAt,
  DateTime? playedAt,
  bool receiptsOff = false,
  // Bundle 218d: set when the server does not know this friend yet.
  String notOnServerName = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    barrierColor: barrierColor,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = theme.colorScheme;
      Widget line(Key key, IconData icon, String label, String value,
              {Color? iconColor}) =>
          Padding(
            key: key,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: iconColor ?? colors.onSurfaceVariant),
                const SizedBox(width: 14),
                Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500))),
                Flexible(
                  child: Text(value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 13.5, color: colors.onSurfaceVariant)),
                ),
              ],
            ),
          );
      final rows = <Widget>[];
      if (group) {
        rows.add(notSentYet
            ? line(const ValueKey('info_not_sent'), Icons.schedule_rounded,
                'Not sent yet', '')
            : line(const ValueKey('info_sent'), Icons.send_rounded, 'Sent',
                messageInfoTime(sentAt)));
      } else {
        // Bundle 218d: a 1:1 message still waiting shows "Not sent yet" too.
        rows.add(notSentYet && deliveredAt == null
            ? line(const ValueKey('info_not_sent'), Icons.schedule_rounded,
                'Not sent yet', '')
            : line(const ValueKey('info_sent'), Icons.send_rounded, 'Sent',
                messageInfoTime(sentAt)));
        if (deliveredAt != null) {
          rows.add(Divider(height: 1, color: colors.outlineVariant));
          rows.add(line(const ValueKey('info_delivered'), Icons.done_all_rounded,
              'Delivered', messageInfoTime(deliveredAt)));
        }
        // Bundle 198: Read (hidden when my switch is OFF) and Played.
        if (readAt != null && !receiptsOff) {
          rows.add(Divider(height: 1, color: colors.outlineVariant));
          rows.add(line(const ValueKey('info_read'), Icons.done_all_rounded,
              'Read', messageInfoTime(readAt),
              iconColor: colors.primary));
        }
        if (playedAt != null) {
          rows.add(Divider(height: 1, color: colors.outlineVariant));
          rows.add(line(const ValueKey('info_played'), Icons.mic_rounded,
              'Played', messageInfoTime(playedAt),
              iconColor: colors.primary));
        }
      }
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Message info',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: preview),
              const SizedBox(height: 8),
              Divider(height: 1, color: colors.outlineVariant),
              ...rows,
              if (!group && deliveredAt != null && receiptsOff)
                Padding(
                  key: const ValueKey('info_receipts_off'),
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Read receipts are off. Turn on in Settings › Privacy.',
                    style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                  ),
                ),
              if (!group && deliveredAt == null && notOnServerName.isNotEmpty) ...[
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: 12),
                Container(
                  key: const ValueKey('info_not_on_server'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$notOnServerName is not on the server yet. It goes when '
                    '$notOnServerName is nearby or joins the server.',
                    style: TextStyle(fontSize: 13.5, color: colors.onSurfaceVariant),
                  ),
                ),
              ],
              if (!group && deliveredAt == null && notOnServerName.isEmpty)
                Padding(
                  key: const ValueKey('info_waiting'),
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Waiting. ${peerName.isEmpty ? 'Your friend' : peerName} '
                    'gets it when they are Nearby or Online.',
                    style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                  ),
                ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Close',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// "Clear chat with Ali?" (mock 16) / "Delete chat with Ali?" (mock 18).
/// True = confirmed.
Future<bool> showClearChatSheet(
  BuildContext context, {
  required String name,
  bool deleteChat = false,
  bool group = false,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = theme.colorScheme;
      Widget point(List<InlineSpan> spans) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7, right: 10),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: colors.onSurfaceVariant, shape: BoxShape.circle),
                  ),
                ),
                Expanded(
                  child: Text.rich(TextSpan(children: spans),
                      style: TextStyle(
                          fontSize: 14, height: 1.35, color: colors.onSurface)),
                ),
              ],
            ),
          );
      const bold = TextStyle(fontWeight: FontWeight.w700);
      final points = deleteChat
          ? [
              point(const [
                TextSpan(text: 'The chat and all its messages, photos and files are '),
                TextSpan(text: 'deleted from this phone', style: bold),
                TextSpan(text: ' and it leaves your Chats list.'),
              ]),
              point([
                TextSpan(
                    text: '$name stays your friend. A new message from them '
                        'starts a new chat.'),
              ]),
            ]
          : [
              point(const [
                TextSpan(text: 'All messages, photos and files in this chat are '),
                TextSpan(text: 'deleted from this phone', style: bold),
                TextSpan(text: '.'),
              ]),
              point(group
                  ? const [
                      TextSpan(text: 'The other members '),
                      TextSpan(text: 'still have', style: bold),
                      TextSpan(text: ' their copy. Photos you saved to your Gallery stay.'),
                    ]
                  : [
                      TextSpan(text: '$name '),
                      const TextSpan(text: 'still has', style: bold),
                      const TextSpan(
                          text: ' their copy. Photos you saved to your Gallery stay.'),
                    ]),
              point(const [
                TextSpan(text: 'The chat stays in your Chats list, empty.'),
              ]),
            ];
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(deleteChat ? 'Delete chat with $name?' : 'Clear chat with $name?',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              ...points,
              const SizedBox(height: 6),
              _wideButton(
                key: ValueKey(deleteChat ? 'confirm_delete_chat' : 'confirm_clear_chat'),
                label: deleteChat ? 'Delete chat' : 'Clear chat',
                filled: true,
                colors: colors,
                onTap: () => Navigator.pop(sheetContext, true),
              ),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return ok ?? false;
}

enum ChatRowChoice { clear, delete }

/// Chats list: hold a chat (mock 17). Groups get Clear chat only.
Future<ChatRowChoice?> showChatRowSheet(
  BuildContext context, {
  required String name,
  required String subtitle,
  required Widget avatar,
  bool allowDelete = true,
}) {
  return showModalBottomSheet<ChatRowChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final colors = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: avatar,
                title: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: subtitle.isEmpty
                    ? null
                    : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              ListTile(
                key: const ValueKey('chat_row_clear'),
                leading: Icon(Icons.clear_all_rounded, color: colors.onSurfaceVariant),
                title: const Text('Clear chat'),
                onTap: () => Navigator.pop(sheetContext, ChatRowChoice.clear),
              ),
              if (allowDelete)
                ListTile(
                  key: const ValueKey('chat_row_delete'),
                  leading: Icon(Icons.delete_outline_rounded, color: colors.error),
                  title: Text('Delete chat', style: TextStyle(color: colors.error)),
                  onTap: () => Navigator.pop(sheetContext, ChatRowChoice.delete),
                ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Close',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Reply bar above the message box (mock 9).
class ReplyBar extends StatelessWidget {
  final String name;
  final String line;
  final bool isYou;
  final VoidCallback onClose;

  /// Bundle 199: small picture of the photo / video being answered.
  final Widget? thumb;

  const ReplyBar({
    super.key,
    required this.name,
    required this.line,
    required this.isYou,
    required this.onClose,
    this.thumb,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = isYou ? kQuoteYouColor : colors.primary;
    return Container(
      key: const ValueKey('reply_bar'),
      color: colors.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: accent, width: 4)),
              ),
              child: _withThumb(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        style: TextStyle(
                            color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: colors.onSurface)),
                  ],
                ),
                thumb,
                expand: true,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('reply_bar_close'),
            tooltip: 'Cancel reply',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// Quote box on top of a bubble (mock 10).
class QuoteBox extends StatelessWidget {
  final String name;
  final String line;
  final bool isYou;
  final bool notAvailable;
  final VoidCallback? onTap;
  final bool onBlue;

  /// Bundle 199: small picture of the quoted photo / video.
  final Widget? thumb;

  const QuoteBox({
    super.key,
    required this.name,
    required this.line,
    required this.isYou,
    this.notAvailable = false,
    this.onTap,
    this.onBlue = false,
    this.thumb,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = onBlue
        ? Colors.white
        : (isYou ? kQuoteYouColor : colors.primary);
    final textColor = onBlue ? Colors.white : colors.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: const ValueKey('bubble_quote'),
        margin: const EdgeInsets.only(bottom: 4),
        // Bundle 202 (mock C3): slimmer box, picture close to the right edge.
        padding: EdgeInsets.fromLTRB(
            7, 3, thumb != null && !notAvailable ? 3 : 6, 3),
        decoration: BoxDecoration(
          color: onBlue
              ? Colors.white.withValues(alpha: .18)
              : colors.onSurface.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: accent, width: 3.5)),
        ),
        child: _withThumb(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!notAvailable)
              Text(name,
                  style: TextStyle(
                      color: accent, fontWeight: FontWeight.w700, fontSize: 12.5)),
            Text(
              notAvailable ? 'Message not available' : line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: textColor.withValues(alpha: notAvailable ? .6 : .9),
                fontStyle: notAvailable ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        ), notAvailable ? null : thumb),
      ),
    );
  }
}

/// Bundle 199: text on the left, the small picture on the right.
/// No picture = exactly the old layout.
Widget _withThumb(Widget text, Widget? thumb, {bool expand = false}) {
  if (thumb == null) return text;
  return Row(
    mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
    children: [
      if (expand) Expanded(child: text) else Flexible(child: text),
      thumb,
    ],
  );
}

/// "↪ Forwarded" (mock 12).
class ForwardedLabel extends StatelessWidget {
  final Color? color;
  const ForwardedLabel({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      key: const ValueKey('bubble_forwarded'),
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forward_rounded, size: 13, color: c),
          const SizedBox(width: 3),
          Text('Forwarded',
              style: TextStyle(
                  fontSize: 11.5, fontStyle: FontStyle.italic, color: c)),
        ],
      ),
    );
  }
}

/// Round check on the left in Select mode (mock 13).
class SelectCheck extends StatelessWidget {
  final bool selected;
  const SelectCheck({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: selected
          ? Icon(Icons.check_circle_rounded, size: 22, color: colors.primary)
          : Icon(Icons.radio_button_unchecked_rounded,
              size: 22, color: colors.outline),
    );
  }
}

/// The bubble-only grey highlight (darker grey + thin ring), TODO 2.3 H8.
BoxDecoration highlightBubble(BoxDecoration base, ColorScheme colors,
    {required bool on, bool gradient = false}) {
  if (!on) return base;
  final ring = Border.all(
      color: gradient
          ? Colors.white.withValues(alpha: .85)
          : colors.outline.withValues(alpha: .75),
      width: 1.6);
  if (gradient) return base.copyWith(border: ring);
  final fill = Color.alphaBlend(
      colors.onSurface.withValues(alpha: .10),
      base.color ?? colors.surfaceContainerHighest);
  return base.copyWith(color: fill, border: ring);
}

/// Bundle 199: after tapping a reply box, the original bubble gets a blue
/// border (the app colour) for 2 s, then it fades out (~0.3 s). No grey fill;
/// Hold / Select keep their grey highlight. Drawn on top of the bubble, so
/// the bubble itself is unchanged.
class FlashRing extends StatelessWidget {
  const FlashRing({
    super.key,
    required this.on,
    required this.radius,
    required this.child,
    this.onBlue = false,
  });

  static const Duration hold = Duration(seconds: 2);
  static const Duration fade = Duration(milliseconds: 300);

  final bool on;
  final BorderRadius radius;
  final Widget child;

  /// Own group bubble (blue gradient): white border instead.
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: on ? 1 : 0,
              duration: still ? Duration.zero : fade,
              child: DecoratedBox(
                key: const ValueKey('bubble_flash_ring'),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                      color: onBlue ? Colors.white : colors.primary, width: 2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dims the whole chat while a sheet is open, but leaves a hole around the
/// held bubble so it shows bright (mock 2-6, 20-21).
class HeldBubbleDimmer extends StatefulWidget {
  final GlobalKey target;
  const HeldBubbleDimmer({super.key, required this.target});

  @override
  State<HeldBubbleDimmer> createState() => _HeldBubbleDimmerState();
}

class _HeldBubbleDimmerState extends State<HeldBubbleDimmer> {
  Rect? _hole;

  void _measure() {
    if (!mounted) return;
    final me = context.findRenderObject();
    final box = widget.target.currentContext?.findRenderObject();
    Rect? next;
    if (me is RenderBox && box is RenderBox && box.attached && me.attached) {
      final topLeft = box.localToGlobal(Offset.zero, ancestor: me);
      next = topLeft & box.size;
    }
    if (next != _hole) setState(() => _hole = next);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('held_dimmer'),
        painter: _HolePainter(_hole),
        size: Size.infinite,
      ),
    );
  }
}

class _HolePainter extends CustomPainter {
  final Rect? hole;
  _HolePainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final paint = Paint()..color = Colors.black.withValues(alpha: .38);
    final h = hole;
    if (h == null) {
      canvas.drawPath(full, paint);
      return;
    }
    final cut = Path()
      ..addRRect(RRect.fromRectAndRadius(h.inflate(1), const Radius.circular(18)));
    canvas.drawPath(Path.combine(PathOperation.difference, full, cut), paint);
  }

  @override
  bool shouldRepaint(_HolePainter old) => old.hole != hole;
}
