import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/connectivity/data/services/nearby_experiments.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 173: the old Settings > "Nearby tests" screen is gone.
///
/// * [NearbyTestSwitches] - the two tests (Link full groups, Share a
///   LocalLink hotspot) now live in the Admin panel, testers only.
/// * [ExtraNearbySafetySwitch] - strict mode, in plain words, in
///   Account > Backup and safety (183).
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
          child: Text(L.t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(L.t.turnOn),
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
              title: Text(L.t.linkFullGroups),
              subtitle: Text(L.t.joinFullNearbyGroupsAsA(x.linkStatusText)),
              value: x.linkGroups,
              onChanged: (on) async {
                if (on &&
                    !await _confirmTurnOn(
                      context,
                      L.t.linkFullGroups2,
                      L.t.androidWillAskConnectEachTime,
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
              title: Text(L.t.shareALinkupHotspot),
              subtitle: Text(L.t.otherLinkupPhonesJoinThisOne(x.hotspotStatusText)),
              value: x.shareHotspot,
              onChanged: (on) async {
                if (on &&
                    !await _confirmTurnOn(
                      context,
                      L.t.shareAHotspot,
                      L.t.thisUsesMoreBatterySomePhones,
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
      // Bundle 183 (B6): a normal Account row - icon in a light circle,
      // the same text sizes as every other row, switch on the right.
      builder: (context, _) => SwitchListTile(
        key: const Key('nearby_strict_link_check'),
        secondary: const MessengerRowIcon(icon: Icons.verified_user_outlined),
        title: Text(L.t.extraNearbySafety,
            style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(L.t.onlyContactsTheAppCanConfirm,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0)),
        value: x.strictLinkCheck,
        onChanged: (on) async {
          if (on &&
              !await _confirmTurnOn(
                context,
                L.t.turnOnExtraNearbySafety,
                L.t.contactsWithAnOlderLinkupWill,
              )) {
            return;
          }
          await x.setStrictLinkCheck(on);
        },
      ),
    );
  }
}
