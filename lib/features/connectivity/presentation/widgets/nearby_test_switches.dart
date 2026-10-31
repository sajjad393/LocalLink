import 'package:flutter/material.dart';
import 'package:locallink/features/connectivity/data/services/nearby_experiments.dart';

/// Bundle 173: the old Settings > "Nearby tests" screen is gone.
///
/// * [NearbyTestSwitches] - the two tests (Link full groups, Share a
///   LocalLink hotspot) now live in the Admin panel, testers only.
/// * [ExtraNearbySafetySwitch] - strict mode, in plain words, in
///   Settings > Privacy & security.
///
/// How the switches work did not change; all stay OFF by default.
Future<bool> _confirmTurnOn(
    BuildContext context, String title, String body) async {
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

class NearbyTestSwitches extends StatelessWidget {
  final NearbyExperiments? experiments;

  const NearbyTestSwitches({super.key, this.experiments});

  @override
  Widget build(BuildContext context) {
    final x = experiments ?? NearbyExperiments.instance;
    return AnimatedBuilder(
      animation: x,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: SwitchListTile(
              key: const Key('nearby_test_link_groups'),
              secondary: const Icon(Icons.hub_outlined),
              title: const Text('Link full groups'),
              subtitle: Text('Join full nearby groups as a Wi-Fi user and '
                  'join a LocalLink hotspot. ${x.linkStatusText}'),
              value: x.linkGroups,
              onChanged: (on) async {
                if (on &&
                    !await _confirmTurnOn(
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
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: SwitchListTile(
              key: const Key('nearby_test_share_hotspot'),
              secondary: const Icon(Icons.wifi_tethering),
              title: const Text('Share a LocalLink hotspot'),
              subtitle: Text('Other LocalLink phones join this one. No '
                  'internet is shared. ${x.hotspotStatusText}'),
              value: x.shareHotspot,
              onChanged: (on) async {
                if (on &&
                    !await _confirmTurnOn(
                      context,
                      'Share a hotspot?',
                      'This uses more battery. Some phones cannot run '
                          'it while on Wi-Fi. Only LocalLink phones with '
                          '"Link full groups" on will join it.',
                    )) {
                  return;
                }
                await x.setShareHotspot(on);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ExtraNearbySafetySwitch extends StatelessWidget {
  final NearbyExperiments? experiments;

  const ExtraNearbySafetySwitch({super.key, this.experiments});

  @override
  Widget build(BuildContext context) {
    final x = experiments ?? NearbyExperiments.instance;
    return AnimatedBuilder(
      animation: x,
      builder: (context, _) => SwitchListTile(
        key: const Key('nearby_strict_link_check'),
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.verified_user_outlined),
        title: const Text('Extra nearby safety'),
        subtitle: const Text(
            'Only connect nearby to contacts the app can confirm.'),
        value: x.strictLinkCheck,
        onChanged: (on) async {
          if (on &&
              !await _confirmTurnOn(
                context,
                'Turn on extra nearby safety?',
                'Contacts with an older LocalLink will not connect nearby '
                    'until they update. Messages through the internet '
                    'still work.',
              )) {
            return;
          }
          await x.setStrictLinkCheck(on);
        },
      ),
    );
  }
}
