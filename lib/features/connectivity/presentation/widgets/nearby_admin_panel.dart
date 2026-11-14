import 'package:flutter/material.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_list_page.dart';
import 'package:locallink/features/connectivity/data/services/nearby_admin_status.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 159.3: read-only "This phone — nearby network" section for the
/// admin Network & Mesh screen: group, host, bridge, members, links, routes
/// with hops, and what this phone passes on for others. No buttons.
class NearbyAdminPanel extends StatefulWidget {
  const NearbyAdminPanel({super.key, this.load});

  /// Defaults to [NearbyAdminStatus.loader].
  final Future<NearbyAdminSnapshot> Function()? load;

  @override
  State<NearbyAdminPanel> createState() => _NearbyAdminPanelState();
}

class _NearbyAdminPanelState extends State<NearbyAdminPanel> {
  NearbyAdminSnapshot? _snapshot;
  bool _failed = false;
  // Bundle 163 (4.9): route list search + paging.
  String _routeQuery = '';
  int _routeShown = kAdminListPage;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final load = widget.load ?? NearbyAdminStatus.loader;
    if (load == null) {
      setState(() => _failed = true);
      return;
    }
    try {
      final s = await load();
      if (mounted) {
        setState(() {
          _snapshot = s;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _snapshot;
    final header = Row(
      children: [
        Expanded(
          child: Text(L.t.thisPhoneNearbyNetwork,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        IconButton(
          tooltip: L.t.refresh,
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
    if (s == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Text(_failed ? L.t.notAvailableOnThisDevice : L.t.loading,
              style: theme.textTheme.bodySmall),
        ],
      );
    }
    final role = switch (s.role) {
      'host' => L.t.host,
      'member' => L.t.member,
      _ => L.t.notInAGroup,
    };
    final rows = <(String, String)>[
      (L.t.group, s.group ?? '—'),
      (L.t.role, role),
      if (s.role == 'host') (L.t.members, '${s.members}'),
      (L.t.bridgeToWiFi, s.bridge ? L.t.yes : 'No'),
      (L.t.onCharger, s.charging ? L.t.yes : 'No'),
      (L.t.nearbyPhonesSeen, '${s.nearbyTags}'),
      (L.t.waitingForARoute, '${s.waiting}'),
      (L.t.directLinks, '${s.directLinks}'),
      (L.t.linksWithCheckedId, '${s.verifiedLinks}'),
      (L.t.relayLinksNotContacts, '${s.relayLinks}'),
      (L.t.callsPassedOnNow, '${s.relayVoiceCalls}'),
      (L.t.packetsPassedOn, '${s.forwardedPackets}'),
      (L.t.voiceFramesPassedOn, '${s.forwardedVoiceFrames}'),
      (L.t.filePartsPassedOn, '${s.forwardedFileChunks}'),
      // Bundle 161 (tests).
      (L.t.linkedGroupHotspotTest, switch (s.localNet) {
        'linked' => s.localNetKind == 'hotspot' ? L.t.hotspot : L.t.group,
        'joining' => L.t.joining,
        _ => 'No',
      }),
      (L.t.sharingAHotspotTest, s.hotspot ? L.t.yes : 'No'),
      (L.t.phonesLinkedThisWay, '${s.localNetPeers}'),
      (L.t.shortRouteList, s.compactMap ? L.t.yes : 'No'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (s.wifiBlocked)
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.wifi_off),
              title: Text(L.t.thisWiFiBlocksPhonesFrom),
              subtitle: Text(L.t.usingNearbyGroupsInstead),
            ),
          ),
        Card(
          child: Column(
            children: [
              for (final r in rows)
                ListTile(
                  dense: true,
                  title: Text(r.$1),
                  trailing: Text(r.$2,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(L.t.routes(s.routes.length),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (s.routes.length > kAdminListSearchFrom)
          AdminListSearch(
            hint: L.t.searchPhoneOrNextHop,
            onChanged: (q) => setState(() {
              _routeQuery = q;
              _routeShown = kAdminListPage;
            }),
          ),
        if (s.routes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(L.t.noRoutesYet, style: theme.textTheme.bodySmall),
          )
        else
          Card(
            child: Column(
              children: [
                for (final r in adminListPage(s.routes,
                        query: _routeQuery,
                        shown: _routeShown,
                        keys: (r) => [r.destination, r.nextHop])
                    .visible)
                  ListTile(
                    dense: true,
                    title: Text(r.destination),
                    subtitle: Text(L.t.via(r.nextHop.isEmpty ? '—' : r.nextHop, r.state.isEmpty || r.state == 'ACTIVE' ? '' : ' · ${r.state.toLowerCase()}')),
                    trailing: Text('${r.hops} ${r.hops == 1 ? 'hop' : 'hops'}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                AdminListMoreButton(
                  shown: _routeShown,
                  matched: adminListPage(s.routes,
                          query: _routeQuery,
                          shown: 0,
                          keys: (r) => [r.destination, r.nextHop])
                      .matched,
                  onPressed: () =>
                      setState(() => _routeShown += kAdminListPage),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
