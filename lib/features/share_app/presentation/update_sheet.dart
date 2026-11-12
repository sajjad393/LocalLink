// Bundle 213 (E) -> Bundle 275 (mock LinkUp_mock_275_silent_update.html):
// ONE popup on the old phone, no names. It starts by itself; the phone with
// the new app shows nothing. The Bundle 213 list with names + Ask and the
// "X wants the new LinkUp" Share / Not now question are gone.

import 'package:flutter/material.dart';
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
              _ => (Icons.download_rounded, const Color(0xFF3B82C4), 'New LinkUp found nearby', sub),
            };
            final getting = s.stage == SilentStage275.getting || s.stage == SilentStage275.nextPhone;
            final frac = s.size > 0 ? (s.got / s.size).clamp(0.0, 1.0) : null;
            return Column(
              key: const ValueKey('update275_sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  CircleAvatar(radius: 20, backgroundColor: tint, child: Icon(icon, color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, key: const ValueKey('update275_title'), style: theme.textTheme.titleMedium),
                      Text(line, style: muted),
                    ]),
                  ),
                ]),
                const SizedBox(height: 14),
                if (getting) ...[
                  LinearProgressIndicator(
                      value: s.stage == SilentStage275.nextPhone || s.got == 0 ? null : frac),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                        child: Text(s.stage == SilentStage275.nextPhone ? 'Trying again…' : 'Getting it…',
                            key: const ValueKey('update275_getting'), style: muted)),
                    Text(
                        s.stage == SilentStage275.nextPhone
                            ? 'Next phone'
                            : (s.got > 0 && s.size > 0 ? '${_mb(s.got)} of ${_mb(s.size)}' : 'Starting'),
                        style: muted),
                  ]),
                  const SizedBox(height: 8),
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
                        borderRadius: BorderRadius.circular(10)),
                    child: Text.rich(TextSpan(children: [
                      const TextSpan(text: 'One time only\n', style: TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(
                          text: 'Android will ask you to allow installs from LinkUp. Turn it on, then come back.',
                          style: muted),
                    ])),
                  ),
                if (s.stage == SilentStage275.none) Text('LinkUp tries again later by itself.', style: muted),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (getting)
                    TextButton(
                      key: const ValueKey('update275_cancel'),
                      onPressed: () {
                        s.cancel();
                        Navigator.of(context).maybePop();
                      },
                      child: const Text('Cancel'),
                    ),
                  if (s.stage == SilentStage275.ready) ...[
                    TextButton(
                      key: const ValueKey('update275_later'),
                      onPressed: () {
                        s.cancel();
                        Navigator.of(context).maybePop();
                      },
                      child: const Text('Later'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('update275_install'),
                      onPressed: s.install,
                      child: const Text('Install'),
                    ),
                  ],
                  if (s.stage == SilentStage275.none || s.stage == SilentStage275.idle)
                    TextButton(
                      key: const ValueKey('update275_ok'),
                      onPressed: () {
                        s.close();
                        Navigator.of(context).maybePop();
                      },
                      child: const Text('OK'),
                    ),
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
