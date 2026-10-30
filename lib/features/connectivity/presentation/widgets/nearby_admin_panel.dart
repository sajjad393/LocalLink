import 'package:flutter/material.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_list_page.dart';
import 'package:locallink/features/connectivity/data/services/nearby_admin_status.dart';

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
          child: Text('This phone — nearby network',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        IconButton(
          tooltip: 'Refresh',
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
          Text(_failed ? 'Not available on this device.' : 'Loading…',
              style: theme.textTheme.bodySmall),
        ],
      );
    }
    final role = switch (s.role) {
      'host' => 'Host',
      'member' => 'Member',
      _ => 'Not in a group',
    };
    final rows = <(String, String)>[
      ('Group', s.group ?? '—'),
      ('Role', role),
      if (s.role == 'host') ('Members', '${s.members}'),
      ('Bridge to Wi-Fi', s.bridge ? 'Yes' : 'No'),
      ('On charger', s.charging ? 'Yes' : 'No'),
      ('Nearby phones seen', '${s.nearbyTags}'),
      ('Waiting for a route', '${s.waiting}'),
      ('Direct links', '${s.directLinks}'),
      ('Links with checked id', '${s.verifiedLinks}'),
      ('Relay links (not contacts)', '${s.relayLinks}'),
      ('Calls passed on now', '${s.relayVoiceCalls}'),
      ('Packets passed on', '${s.forwardedPackets}'),
      ('Voice frames passed on', '${s.forwardedVoiceFrames}'),
      // Bundle 161 (tests).
      ('Linked group / hotspot (test)', switch (s.localNet) {
        'linked' => s.localNetKind == 'hotspot' ? 'Hotspot' : 'Group',
        'joining' => 'Joining…',
        _ => 'No',
      }),
      ('Sharing a hotspot (test)', s.hotspot ? 'Yes' : 'No'),
      ('Phones linked this way', '${s.localNetPeers}'),
      ('Short route list', s.compactMap ? 'Yes' : 'No'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (s.wifiBlocked)
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.wifi_off),
              title: Text('This Wi-Fi blocks phones from seeing each other'),
              subtitle: Text('Using nearby groups instead.'),
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
        Text('Routes (${s.routes.length})',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (s.routes.length > kAdminListSearchFrom)
          AdminListSearch(
            hint: 'Search phone or next hop',
            onChanged: (q) => setState(() {
              _routeQuery = q;
              _routeShown = kAdminListPage;
            }),
          ),
        if (s.routes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No routes yet.', style: theme.textTheme.bodySmall),
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
                    subtitle: Text('via ${r.nextHop.isEmpty ? '—' : r.nextHop}'
                        '${r.state.isEmpty || r.state == 'ACTIVE' ? '' : ' · ${r.state.toLowerCase()}'}'),
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
