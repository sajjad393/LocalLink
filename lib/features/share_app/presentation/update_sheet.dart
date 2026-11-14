import 'dart:async';

// Bundle 213 (E) -> Bundle 275 (mock LinkUp_mock_275_silent_update.html):
// ONE popup on the old phone, no names. It starts by itself; the phone with
// the new app shows nothing. The Bundle 213 list with names + Ask and the
// "X wants the new LinkUp" Share / Not now question are gone.

import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/chat_notice_bar_302.dart';
import 'package:locallink/features/share_app/domain/silent_update_275.dart';

/// The Update button (version banner): the same quiet flow.
Future<void> showUpdateSheet(BuildContext context) async {
  final s = SilentUpdate275.instance;
  if (s == null) return;
  await s.check(manual: true);
}

/// Opens the popup for [s] (bottom sheet; swipe down = keeps going quietly).
Future<void> showSilentUpdateSheet275(BuildContext context, SilentUpdate275 s) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SilentUpdateSheet275(service: s),
    );

String _mb(int bytes) =>
    bytes <= 0 ? '' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

class SilentUpdateSheet275 extends StatelessWidget {
  const SilentUpdateSheet275({super.key, required this.service});

  final SilentUpdate275 service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            final s = service;
            final ver = s.version.isEmpty ? 'Version newer' : 'Version ${s.version}';
            final size = _mb(s.size);
            final sub = size.isEmpty ? ver : '$ver · $size';
            final (IconData icon, Color tint, String title, String line) = switch (s.stage) {
              SilentStage275.ready => (Icons.check_circle_rounded, const Color(0xFF12A150), 'Ready to update',
                  'LinkUp${s.version.isEmpty ? '' : ' ${s.version}'} is downloaded'),
              SilentStage275.none => (Icons.system_update_rounded, theme.colorScheme.outline, 'Could not get it now',
                  'No nearby phone could share it'),
              SilentStage275.nextPhone => (Icons.download_rounded, const Color(0xFF3B82C4),
                  'Getting it from another phone', sub),
              // Bundle 299 (C): the server has it.
              _ when s.fromServer => (Icons.dns_rounded, const Color(0xFF3B82C4), 'New LinkUp on the server', sub),
              _ => (Icons.download_rounded, const Color(0xFF3B82C4), 'New LinkUp found nearby', sub),
            };
            final getting = s.stage == SilentStage275.getting || s.stage == SilentStage275.nextPhone;
            final frac = s.size > 0 ? (s.got / s.size).clamp(0.0, 1.0) : null;
            // Bundle 302 (D): bigger round icon, clear progress, pill buttons
            // and Try again (mock labels_footer_302.html).
            final pct = frac == null ? '' : ' · ${(frac * 100).round()}%';
            return Column(
              key: const ValueKey('update275_sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  CircleAvatar(
                      radius: 23,
                      backgroundColor: s.stage == SilentStage275.none
                          ? theme.colorScheme.surfaceContainerHighest
                          : tint,
                      child: Icon(icon,
                          color: s.stage == SilentStage275.none
                              ? theme.colorScheme.onSurfaceVariant
                              : Colors.white,
                          size: 24)),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          key: const ValueKey('update275_title'),
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(line, style: muted),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                if (getting) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        minHeight: 8,
                        value: s.stage == SilentStage275.nextPhone || s.got == 0 ? null : frac),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: Text(
                            s.stage == SilentStage275.nextPhone
                                ? 'Trying again…'
                                : (s.fromServer ? 'Getting it from the server…' : 'Getting it…'),
                            key: const ValueKey('update275_getting'), style: muted)),
                    Text(
                        s.stage == SilentStage275.nextPhone
                            ? 'Next phone'
                            : (s.got > 0 && s.size > 0 ? '${(s.got / (1024 * 1024)).toStringAsFixed(1)} of ${_mb(s.size)}$pct' : 'Starting'),
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                      s.stage == SilentStage275.nextPhone
                          ? 'This happens by itself.'
                          : 'Started by itself. You can keep using LinkUp.',
                      style: muted),
                ],
                if (s.stage == SilentStage275.ready && s.needsAllow)
                  Container(
                    key: const ValueKey('update275_once'),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text.rich(TextSpan(children: [
                      const TextSpan(text: 'One time only\n', style: TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(
                          text: 'Android will ask you to allow installs from LinkUp. Turn it on, then come back.',
                          style: muted),
                    ])),
                  ),
                if (s.stage == SilentStage275.none) Text('LinkUp tries again later by itself.', style: muted),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (getting)
                    NoticeButton302(
                      key: const ValueKey('update275_cancel'),
                      label: 'Cancel',
                      filled: false,
                      onPressed: () {
                        s.cancel();
                        Navigator.of(context).maybePop();
                      },
                    ),
                  if (s.stage == SilentStage275.ready) ...[
                    NoticeButton302(
                      key: const ValueKey('update275_later'),
                      label: 'Later',
                      filled: false,
                      onPressed: () {
                        s.cancel();
                        Navigator.of(context).maybePop();
                      },
                    ),
                    const SizedBox(width: 8),
                    NoticeButton302(
                      key: const ValueKey('update275_install'),
                      label: 'Install',
                      onPressed: s.install,
                    ),
                  ],
                  if (s.stage == SilentStage275.none || s.stage == SilentStage275.idle)
                    NoticeButton302(
                      key: const ValueKey('update275_ok'),
                      label: 'OK',
                      filled: false,
                      onPressed: () {
                        s.close();
                        Navigator.of(context).maybePop();
                      },
                    ),
                  // Bundle 302 (D): ask the server / nearby phones again now.
                  if (s.stage == SilentStage275.none) ...[
                    const SizedBox(width: 8),
                    NoticeButton302(
                      key: const ValueKey('update275_retry'),
                      label: 'Try again',
                      onPressed: () => unawaited(s.check(manual: true)),
                    ),
                  ],
                ]),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Bundle 213 card on Chats: gone in 275 (the popup shows the progress).
class UpdateOfferCard extends StatelessWidget {
  const UpdateOfferCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
