import 'package:flutter/material.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/calls/presentation/call_history_groups.dart';

/// Bundle 298 (F): calls with this friend inside the chat, WhatsApp style.
///
/// - A bubble on the side of the person who called (mine = right).
/// - Phone icon + "Voice call" and a second line: the length ("2:15") or
///   what happened ("No answer", "Declined", ...). The same words as the
///   Calls tab.
/// - An incoming call I never answered: red "Missed voice call".
/// - Tap = call back (when calling is allowed in this chat).
/// - Comes from the saved Calls history, so old calls show too. Group
///   calls and the call that is still going on are not shown.
class CallBubble298 extends StatelessWidget {
  const CallBubble298({super.key, required this.call, required this.selfId, this.onCallBack});

  final CallRecord call;
  final String selfId;
  final VoidCallback? onCallBack;

  /// The calls with [peerId], oldest first ([history] is newest first).
  static List<CallRecord> forChat(List<CallRecord> history,
      {required String selfId, required String peerId, String? liveId}) {
    if (peerId.isEmpty) return const <CallRecord>[];
    final out = [
      for (final c in history)
        if (c.peerId(selfId) == peerId && c.id != liveId) c,
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return out;
  }

  /// Calls between message times [after] (null = from the start) and
  /// [before] - the bubbles drawn just above the message at [before].
  static List<CallRecord> between(List<CallRecord> calls, DateTime? after, DateTime before) => [
        for (final c in calls)
          if ((after == null || !c.startedAt.isBefore(after)) && c.startedAt.isBefore(before)) c,
      ];

  /// Calls after the last message.
  static List<CallRecord> after(List<CallRecord> calls, DateTime last) => [
        for (final c in calls)
          if (!c.startedAt.isBefore(last)) c,
      ];

  static bool missed(CallRecord c, String selfId) => isMissedIncoming(c, selfId);

  /// First line.
  static String title(CallRecord c, String selfId) => missed(c, selfId) ? 'Missed voice call' : 'Voice call';

  /// Second line: length, or what happened (Calls tab words).
  static String detail(CallRecord c, String selfId) {
    if (missed(c, selfId)) return 'Tap to call back';
    if (c.durationSeconds > 0) {
      return '${c.durationSeconds ~/ 60}:${(c.durationSeconds % 60).toString().padLeft(2, '0')}';
    }
    return switch (c.status) {
      'rejected' => c.endReason == 'busy' ? 'Busy' : 'Declined',
      'canceled' => 'Canceled',
      'failed' => 'Failed',
      _ => 'No answer',
    };
  }

  static String _time(DateTime raw) {
    final v = raw.toLocal();
    final h = v.hour % 12 == 0 ? 12 : v.hour % 12;
    return '$h:${v.minute.toString().padLeft(2, '0')} ${v.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mine = call.isOutgoing(selfId);
    final isMissed = missed(call, selfId);
    final answered = call.durationSeconds > 0 || call.answeredAt != null;
    const red = Color(0xFFDC2626);
    const green = Color(0xFF16A34A);
    final tone = isMissed ? red : (answered ? green : colors.onSurfaceVariant);
    final icon = isMissed ? Icons.phone_missed_rounded : (mine ? Icons.call_made_rounded : Icons.call_received_rounded);
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(LocalLinkRadius.chat),
      topRight: const Radius.circular(LocalLinkRadius.chat),
      bottomLeft: Radius.circular(mine ? LocalLinkRadius.chat : 6),
      bottomRight: Radius.circular(mine ? 6 : LocalLinkRadius.chat),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: LocalLinkSpacing.xs),
        child: Semantics(
          button: onCallBack != null,
          label: '${title(call, selfId)}, ${detail(call, selfId)}, ${_time(call.startedAt)}',
          child: Material(
            color: mine ? colors.surfaceContainer : colors.surfaceContainerHighest,
            borderRadius: radius,
            child: InkWell(
              key: ValueKey('call_bubble_298_${call.id}'),
              borderRadius: radius,
              onTap: onCallBack,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 14, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: tone.withValues(alpha: .14), shape: BoxShape.circle),
                      child: Icon(icon, size: 20, color: tone),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title(call, selfId),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isMissed ? red : colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          detail(call, selfId),
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(width: 18),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _time(call.startedAt),
                        style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurface.withValues(alpha: .62)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
