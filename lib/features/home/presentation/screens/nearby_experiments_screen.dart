import 'package:flutter/material.dart';
import 'package:locallink/features/connectivity/data/services/nearby_experiments.dart';

/// Bundle 161: Settings > Advanced > Nearby tests. Two switches, both off by
/// default. Turning one on first explains what Android will show.
class NearbyExperimentsScreen extends StatelessWidget {
  final NearbyExperiments? experiments;

  const NearbyExperimentsScreen({super.key, this.experiments});

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final x = experiments ?? NearbyExperiments.instance;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby tests')),
      body: AnimatedBuilder(
        animation: x,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'These are tests. They help when many phones are around and '
                'there is no Wi-Fi. Both are off unless you turn them on.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SwitchListTile(
                key: const Key('nearby_test_link_groups'),
                secondary: const Icon(Icons.hub_outlined),
                title: const Text('Link full groups'),
                subtitle: Text(
                    'When a nearby group is full, join it as a Wi-Fi user so '
                    'both groups reach each other. Also joins a LocalLink '
                    'hotspot nearby.\n${x.linkStatusText}'),
                isThreeLine: true,
                value: x.linkGroups,
                onChanged: (on) async {
                  if (on &&
                      !await _confirm(
                        context,
                        'Link full groups?',
                        'Android will ask "Connect?" each time this phone '
                            'joins another group or hotspot. Tap Connect to '
                            'allow it. Needs Android 10 or newer.',
                      )) {
                    return;
                  }
                  await x.setLinkGroups(on);
                },
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SwitchListTile(
                key: const Key('nearby_test_share_hotspot'),
                secondary: const Icon(Icons.wifi_tethering),
                title: const Text('Share a LocalLink hotspot'),
                subtitle: Text(
                    'Nearby LocalLink phones can join this phone like a '
                    'Wi-Fi network. No internet is shared.\n'
                    '${x.hotspotStatusText}'),
                isThreeLine: true,
                value: x.shareHotspot,
                onChanged: (on) async {
                  if (on &&
                      !await _confirm(
                        context,
                        'Share a hotspot?',
                        'This uses more battery. Some phones cannot run '
                            'it while on Wi-Fi. Only '
                            'LocalLink phones with "Link full groups" on '
                            'will join it.',
                      )) {
                    return;
                  }
                  await x.setShareHotspot(on);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
