import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/features/admin/data/actions/admin_action_offline.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';

/// Bundle 216 (page 14): Devices + the phone sheet.
class AdminDevicesScreen extends StatefulWidget {
  const AdminDevicesScreen({super.key});

  @override
  State<AdminDevicesScreen> createState() => _AdminDevicesScreenState();
}

class _AdminDevicesScreenState extends State<AdminDevicesScreen> {
  String _q = '';

  static String owner(Map<String, dynamic> d) =>
      personName216({'display_name': d['display_name'], 'username': d['username']},
          fallback: 'No owner');

  static bool online(Map<String, dynamic> d) => d['online'] == true;

  bool _match(Map<String, dynamic> d) {
    final q = _q.trim().toLowerCase().replaceFirst('@', '');
    if (q.isEmpty) return true;
    return '${d['name'] ?? ''} ${d['display_name'] ?? ''} ${d['username'] ?? ''}'
        .toLowerCase()
        .contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'Devices',
      module: 'Devices',
      subtitle: (s) =>
          '${plural216(s.devices.length, 'phone')} · ${s.devices.where(online).length} online',
      builder: (context, state) {
        final rows = state.devices.where(_match).toList();
        return [
          AdminSearch216(
            hint: 'Search phone or owner',
            fieldKey: const ValueKey('a216_devices_search'),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 12),
          if (state.loading && state.devices.isEmpty)
            const AdminLoading216()
          else if (rows.isEmpty)
            const AdminEmptyState216(
                icon: Icons.smartphone_rounded,
                tone: A216Tone.grey,
                title: 'No phones found',
                body: 'Try another name.')
          else
            AdminListCard216([
              for (final d in rows)
                () {
                  final link = deviceLink216(d);
                  final removed = link.text == 'Removed';
                  return AdminRow216(
                    key: ValueKey('a216_device_${d['id']}'),
                    height: 64,
                    leading: ServerPersonAvatar216(
                      name: owner(d),
                      userId: '${d['user_id'] ?? ''}',
                      deviceId: '${d['id']}',
                      hasAvatar: d['has_avatar'] == true,
                      grey: removed,
                    ),
                    title: '${d['name'] ?? 'Phone'}',
                    subtitle:
                        '${owner(d)} · ${online(d) ? 'online' : age216(d['last_seen_at'])}',
                    titleColor: removed ? A216.colors(context).grey2 : null,
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: AdminTag216(link.text, link.tone),
                    ),
                    onTap: () => showDeviceSheet216(context, d),
                  );
                }(),
            ]),
        ];
      },
    );
  }
}

Future<void> showDeviceSheet216(BuildContext context, Map<String, dynamic> device) {
  final bloc = context.read<AdminBloc>();
  return showAdminSheet216<void>(context,
      builder: (_) => BlocProvider.value(value: bloc, child: _DeviceSheet(device: device)));
}

class _DeviceSheet extends StatefulWidget {
  const _DeviceSheet({required this.device});
  final Map<String, dynamic> device;

  @override
  State<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<_DeviceSheet> {
  String? _wifi;
  bool _loaded = false;
  late String _name = '${widget.device['name'] ?? 'Phone'}';

  String get _id => '${widget.device['id']}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await context.read<AdminBloc>().deviceNetworkPolicy(_id);
    if (!mounted) return;
    setState(() {
      _wifi = wifiRuleOf216(p, device: true);
      _loaded = true;
    });
  }

  Future<void> _setWifi(String? v) async {
    final saved =
        await context.read<AdminBloc>().updateDeviceNetworkPolicy(_id, wifiRadioPolicy: v);
    if (saved != null && mounted) setState(() => _wifi = v);
    // Bundle 220: no server -> the Wi-Fi rule goes as a card to all phones.
    final note = await AdminActionOffline.ifOffline(
      action: 'wifi_rule',
      userId: '${widget.device['user_id'] ?? ''}',
      label: _name,
      devices: [_id],
      detail: {'level': 'device', 'wifi_radio_policy': v ?? ''},
      words: v ?? 'no rule',
    );
    if (note != null && mounted) adminSnack216(context, note);
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: _name);
    final name = await showAdminSheet216<String>(context, builder: (sheet) {
      final t = A216Text.of(sheet);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Rename phone', style: t.sheetTitle),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('a216_rename_field'),
          controller: ctrl,
          autofocus: true,
          maxLength: 64,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        AdminButton216('Save',
            key: const ValueKey('a216_rename_save'),
            onTap: () => Navigator.of(sheet).pop(ctrl.text.trim())),
      ]);
    });
    ctrl.dispose();
    if (name == null || name.isEmpty || name == _name || !mounted) return;
    await context.read<AdminBloc>().rename(_id, name);
    if (mounted) setState(() => _name = name);
  }

  Future<void> _remove() async {
    final ok = await confirmAdmin216(context,
        title: 'Remove this phone?',
        body: 'It is signed out and must sign in again.',
        yes: 'Remove phone',
        danger: true);
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    await context.read<AdminBloc>().revoke(_id);
    // Bundle 220: no server -> a "remove phone" card for all phones.
    final note = await AdminActionOffline.ifOffline(
        action: 'remove_phone',
        userId: '${widget.device['user_id'] ?? ''}',
        label: _name,
        devices: [_id]);
    if (note != null && mounted) adminSnack216(context, note);
    if (nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final bloc = context.read<AdminBloc>();
    final d = widget.device;
    final canManage = AdminPermissions.canManageDevices(bloc.adminRole);
    final canWifi = AdminPermissions.canManageNetworkPolicy(bloc.adminRole);
    final owner = _AdminDevicesScreenState.owner(d);
    final build = d['app_build'];
    final link = deviceLink216(d);
    final edge = edgeOf216(bloc.state.linkMapData, _id);
    final linkNow = edge.link.isEmpty
        ? link.text
        : (edge.other.isEmpty
            ? linkWord216(edge.link)
            : '${linkWord216(edge.link)}, through ${edge.other}');
    final online = d['online'] == true;
    const picks = wifiRuleValues216;
    return Column(
      key: const ValueKey('a216_device_sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_name, style: t.sheetTitle),
        const SizedBox(height: 3),
        Text(
            [
              owner,
              'Android',
              if (build is num && build > 0) 'build $build',
            ].join(' · '),
            style: t.cardSub),
        const AdminSection216('Wi-Fi rule'),
        Opacity(
          opacity: canWifi && _loaded ? 1 : 0.5,
          child: IgnorePointer(
            ignoring: !canWifi || !_loaded,
            child: AdminChips216(
              wrap: true,
              items: [for (final v in picks) wifiRuleLabel216(v)],
              selected: picks.indexOf(_wifi),
              keys: [
                for (final v in picks)
                  ValueKey('a216_device_wifi_${(v ?? 'default')}')
              ],
              onSelected: (i) => _setWifi(picks[i]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Default = same as $owner’s account', style: t.note),
        const SizedBox(height: 10),
        AdminKeyValue216('Owner',
            '$owner${(d['username'] ?? '').toString().isEmpty ? '' : ' (@${d['username']})'}'),
        AdminKeyValue216('Link now', linkNow),
        AdminKeyValue216('Last seen', online ? 'now' : age216(d['last_seen_at'])),
        if (canManage) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: AdminButton216('Rename',
                  key: const ValueKey('a216_rename'),
                  icon: Icons.edit_outlined,
                  kind: A216ButtonKind.outline,
                  height: 42,
                  onTap: _rename),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AdminButton216('Remove phone',
                  key: const ValueKey('a216_remove'),
                  kind: A216ButtonKind.danger,
                  height: 42,
                  onTap: link.text == 'Removed' ? null : _remove),
            ),
          ]),
        ],
      ],
    );
  }
}
