import 'package:flutter/material.dart';

import 'package:locallink/core/utils/phone_label_255.dart';
import 'package:locallink/core/widgets/admin_crown.dart';

import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';

/// Bundle 216 (page 16): Network & mesh — how phones are linked.
class AdminNetworkScreen extends StatelessWidget {
  const AdminNetworkScreen({super.key});

  static int _n(Map<String, dynamic>? m, String k) => (m?[k] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'Network & mesh',
      module: 'Network & Mesh',
      subtitle: (_) => 'How phones are linked',
      builder: (context, state) {
        final c = A216.colors(context);
        final t = A216Text(c);
        final net = state.networkData;
        Widget tile(String key, int n, String label, Color bar, IconData icon) => Expanded(
              child: AdminCard216(
                key: ValueKey('a216_net_$key'),
                height: 76,
                child: Stack(children: [
                  Positioned(
                    left: 14,
                    top: 14,
                    child: Container(
                        width: 4,
                        height: 48,
                        decoration: BoxDecoration(
                            color: bar, borderRadius: BorderRadius.circular(2))),
                  ),
                  Positioned(
                    left: 28,
                    top: 14,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$n', style: t.tileBig),
                      const SizedBox(height: 4),
                      Text(label, style: t.tileSmall),
                    ]),
                  ),
                  Positioned(right: 14, top: 14, child: Icon(icon, size: 18, color: bar)),
                ]),
              ),
            );
        final online = [
          for (final d in state.devices)
            if (d['online'] == true && deviceLink216(d).text != 'Removed') d
        ];
        String how(Map<String, dynamic> d) {
          final owner = personName216(
              {'display_name': d['display_name'], 'username': d['username']},
              fallback: 'No owner');
          final e = edgeOf216(state.linkMapData, '${d['id']}');
          final words = switch (e.link) {
            'server' => 'to the server',
            'wifi_direct' => e.other.isEmpty ? 'Wi-Fi Direct' : 'with ${e.other}',
            'mesh' => e.other.isEmpty ? 'mesh' : 'through ${e.other}',
            'lan' => 'same Wi-Fi',
            _ => switch (deviceLink216(d).text) {
                'Server' => 'to the server',
                'Local Wi-Fi' => 'same Wi-Fi',
                final x => x,
              },
          };
          return '$owner · $words';
        }

        return [
          if (state.loading && net == null) const AdminLoading216(),
          Row(children: [
            tile('server', _n(net, 'server_connected'), 'Server', A216.linkServer,
                Icons.cloud_outlined),
            const SizedBox(width: 10),
            tile('wifi_direct', _n(net, 'wifi_direct_connected'), 'Wi-Fi Direct',
                A216.linkWifiDirect, Icons.wifi_tethering_rounded),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            tile('mesh', _n(net, 'mesh_available'), 'Mesh', A216.linkMesh, Icons.hub_outlined),
            const SizedBox(width: 10),
            tile('lan', _n(net, 'lan_available'), 'Local Wi-Fi', A216.linkLan,
                Icons.router_outlined),
          ]),
          AdminSection216('Phones right now',
              right: '${online.length} online', rightColor: c.grey),
          if (online.isEmpty)
            const AdminEmptyState216(
                icon: Icons.wifi_off_rounded,
                tone: A216Tone.grey,
                title: 'No phones online',
                body: 'Phones show here when they are linked.')
          else
            AdminListCard216([
              for (final d in online)
                AdminRow216(
                  key: ValueKey('a216_net_phone_${d['id']}'),
                  // Bundle 255 B1 (as Users 222): an admin row is taller and
                  // its photo sits lower, so the card never cuts the crown.
                  height: _crowned255(d) ? 62 + _crownExtra255 : 62,
                  leading: Padding(
                    padding: EdgeInsets.only(top: _crowned255(d) ? _crownExtra255 : 0),
                    child: ServerPersonAvatar216(
                    name: personName216(
                        {'display_name': d['display_name'], 'username': d['username']},
                        fallback: '?'),
                    userId: '${d['user_id'] ?? ''}',
                    deviceId: '${d['id']}',
                    hasAvatar: d['has_avatar'] == true,
                  ),
                  ),
                  // Bundle 255 B9: "<owner>'s phone" for a default name.
                  title: phoneTitle255(
                      '${d['name'] ?? ''}',
                      personName216(
                          {'display_name': d['display_name'], 'username': d['username']},
                          fallback: '')),
                  subtitle: how(d),
                  // Bundle 255 B9: every link of the phone, as the tiles.
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Wrap(
                        key: ValueKey('a216_net_links_${d['id']}'),
                        alignment: WrapAlignment.end,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final l in deviceLinks255(d)) AdminTag216(l.text, l.tone),
                        ],
                      ),
                    ),
                  ),
                ),
            ]),
          const SizedBox(height: 12),
          const AdminNote216('Wi-Fi rule: open a person in Users or a phone in Devices.'),
        ];
      },
    );
  }
}

/// Bundle 255 B1: a 20 px photo in a 62 px row has 11 px above it.
final double _crownExtra255 = AdminCrownRoom.extraFor(20, already: 11) + 2;

bool _crowned255(Map d) {
  final user = '${d['user_id'] ?? ''}';
  final dev = '${d['id'] ?? ''}';
  if (user.isEmpty && dev.isEmpty) return false;
  return AdminCrown.showFor(user, dev);
}
