// Bundle 213 (E, mock pages 6-8): get the new LinkUp from a nearby phone.

import 'package:flutter/material.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/share_app/data/app_share_channel.dart';
import 'package:locallink/features/share_app/domain/update_request_service.dart';

Future<void> showUpdateSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const UpdateSheet(),
    );

String _mb(int bytes) =>
    bytes <= 0 ? '' : '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';

/// Mock page 6: phones near me with the new version, Ask, waiting note.
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key, this.service});

  final UpdateRequestService? service;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  List<UpdateCandidate>? _list;

  UpdateRequestService? get _svc => widget.service ?? UpdateRequestService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = _svc;
    final min = VersionGuard.instance.rule?.minBuild ?? 0;
    final list = svc == null ? <UpdateCandidate>[] : await svc.candidates(minBuild: min);
    if (mounted) setState(() => _list = list);
  }

  String _need() {
    final v = VersionGuard.instance.rule?.minVersion ?? '';
    return v.isEmpty ? 'From a nearby phone that has a newer LinkUp' : 'From a nearby phone that has $v or newer';
  }

  @override
  Widget build(BuildContext context) {
    final svc = _svc;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: ListenableBuilder(
          listenable: svc ?? ChangeNotifier(),
          builder: (context, _) {
            final list = _list;
            String? waitingFor;
            for (final c in list ?? const <UpdateCandidate>[]) {
              if (svc?.statusOf(c.peerId) == AskStatus.asking) waitingFor = c.name;
            }
            return Column(
              key: const ValueKey('update_sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Get the new LinkUp', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(_need(), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (list == null)
                  const Padding(
                      padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                else if (list.isEmpty)
                  Padding(
                    key: const ValueKey('update_sheet_empty'),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                        'No nearby phone with the new LinkUp yet. Ask a friend who has it to open LinkUp near you.',
                        style: theme.textTheme.bodyMedium),
                  )
                else
                  for (final c in list) _row(context, svc!, c),
                if (waitingFor != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Waiting for $waitingFor to tap Share (up to 1 min)…',
                        key: const ValueKey('update_sheet_waiting'),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                if (svc?.offer != null) ...[
                  const SizedBox(height: 12),
                  UpdateOfferCard(service: svc),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('update_sheet_cancel'),
                    onPressed: () {
                      svc?.cancel();
                      Navigator.of(context).maybePop();
                    },
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, UpdateRequestService svc, UpdateCandidate c) {
    final theme = Theme.of(context);
    final status = svc.statusOf(c.peerId);
    final line = switch (status) {
      AskStatus.notNow => '${c.name} said not now',
      AskStatus.noAnswer => 'No answer from ${c.name}. Try again in 2 min.',
      AskStatus.failed => "${c.name} can't share now",
      AskStatus.sharing => 'Opening the download…',
      AskStatus.qr => "Scan the QR code on ${c.name}'s phone",
      _ => 'LinkUp ${c.version.isEmpty ? 'newer' : c.version} · Nearby',
    };
    return Padding(
      key: ValueKey('update_row_${c.peerId}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          child: Text(c.name.isEmpty ? '?' : c.name.characters.first.toUpperCase()),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: theme.textTheme.titleSmall),
            Text(line, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        if (status == AskStatus.asking)
          const Text('Asking…', key: ValueKey('update_asking'))
        else
          FilledButton.tonal(
            key: ValueKey('update_ask_${c.peerId}'),
            onPressed: status == AskStatus.sharing ? null : () => svc.ask(c.peerId),
            child: const Text('Ask'),
          ),
      ]),
    );
  }
}

/// Mock page 7: on the phone with the new version.
Future<bool?> showUpdateAskDialog(
    BuildContext context, UpdateAsk ask, ApkInfo apk, ShareBattery battery) {
  final low = !battery.charging && battery.level >= 0 && battery.level <= 10;
  final size = _mb(apk.size);
  final version = apk.version.isEmpty ? 'LinkUp' : 'LinkUp ${apk.version}';
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('update_ask_dialog'),
      title: Text('${ask.name} wants the new LinkUp'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Share $version${size.isEmpty ? '' : ' ($size)'} with ${ask.name} from this phone. '
            'It goes over Wi-Fi, no internet needed.'),
        if (battery.level >= 0) ...[
          const SizedBox(height: 8),
          Text(low ? 'Battery ${battery.level}%. Sharing uses battery.' : 'Battery ${battery.level}%',
              style: TextStyle(color: low ? const Color(0xFFB42318) : null)),
        ],
      ]),
      actions: [
        TextButton(
          key: const ValueKey('update_ask_not_now'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const ValueKey('update_ask_share'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(low ? 'Share anyway' : 'Share'),
        ),
      ],
    ),
  );
}

/// Mock page 8: the other phone is sharing (Open download), or the QR way.
class UpdateOfferCard extends StatelessWidget {
  const UpdateOfferCard({super.key, this.service});

  final UpdateRequestService? service;

  @override
  Widget build(BuildContext context) {
    final svc = service ?? UpdateRequestService.instance;
    if (svc == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final o = svc.offer;
        if (o == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final title = o.qr
            ? 'Only linked by mesh (no direct Wi-Fi)?'
            : '${o.name} is sharing LinkUp ${o.version}';
        final body = o.qr
            ? "${o.name}'s phone shows a QR code. Scan it with your camera to join and download."
            : 'If the download did not open, tap Open download. Chrome may ask: tap Download anyway.';
        return Padding(
          key: ValueKey(o.qr ? 'update_offer_qr' : 'update_offer_card'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Material(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(children: [
                Icon(o.qr ? Icons.qr_code_2 : Icons.download, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(body, style: theme.textTheme.bodySmall),
                  ]),
                ),
                if (!o.qr)
                  TextButton(
                    key: const ValueKey('update_open_download'),
                    onPressed: svc.openOffer,
                    child: const Text('Open download'),
                  ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: svc.clearOffer,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
