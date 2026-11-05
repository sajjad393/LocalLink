import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';

/// Bundle 216 (pages 12-13): Users + the user sheet.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

const _filters = ['All', 'Admins', 'Active', 'Stopped'];

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _q = '';
  int _filter = 0;

  static bool _isAdmin(Map<String, dynamic> u) => (u['admin_role'] ?? '').toString().isNotEmpty;

  bool _match(Map<String, dynamic> u) {
    final status = '${u['status'] ?? 'active'}';
    final ok = switch (_filter) {
      1 => _isAdmin(u),
      2 => status == 'active',
      3 => status == 'suspended' || status == 'disabled',
      _ => true,
    };
    if (!ok) return false;
    final q = _q.trim().toLowerCase().replaceFirst('@', '');
    if (q.isEmpty) return true;
    return '${u['display_name'] ?? ''} ${u['username'] ?? ''}'.toLowerCase().contains(q);
  }

  static String sub(Map<String, dynamic> u) {
    final n = (u['devices'] as num?)?.toInt() ?? 0;
    final phones = n == 0 ? 'no phone' : plural216(n, 'phone');
    if (_isAdmin(u)) return '${level216(u['admin_role'])} · $phones';
    return '@${u['username'] ?? ''} · $phones';
  }

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'Users',
      module: 'Users',
      subtitle: (s) =>
          '${people216(s.users.length)} · ${plural216(s.users.where(_isAdmin).length, 'admin')}',
      builder: (context, state) {
        final rows = state.users.where(_match).toList();
        return [
          AdminSearch216(
            hint: 'Search name or @username',
            fieldKey: const ValueKey('a216_users_search'),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 10),
          AdminChips216(
            items: _filters,
            selected: _filter,
            keys: [for (final f in _filters) ValueKey('a216_users_filter_${f.toLowerCase()}')],
            onSelected: (i) => setState(() => _filter = i),
          ),
          const SizedBox(height: 12),
          if (state.loading && state.users.isEmpty)
            const AdminLoading216()
          else if (rows.isEmpty)
            const AdminEmptyState216(
                icon: Icons.search_rounded,
                tone: A216Tone.grey,
                title: 'No one found',
                body: 'Try another name or filter.')
          else
            AdminListCard216([
              for (final u in rows)
                AdminRow216(
                  key: ValueKey('a216_user_${u['id']}'),
                  height: 64,
                  leading: ServerPersonAvatar216(
                    name: personName216(u, fallback: '?'),
                    userId: '${u['id']}',
                    hasAvatar: u['has_avatar'] == true,
                    admin: _isAdmin(u),
                    grey: '${u['status'] ?? 'active'}' != 'active',
                    online: ((u['online_devices'] as num?) ?? 0) > 0,
                  ),
                  title: personName216(u, fallback: '${u['id']}'),
                  subtitle: sub(u),
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: AdminTag216(userStatus216(u['status']).text,
                        userStatus216(u['status']).tone,
                        dot: true),
                  ),
                  onTap: () => showUserSheet216(context, u),
                ),
            ]),
        ];
      },
    );
  }
}

/// Page 13: the user sheet (status, Wi-Fi rule, sign out all phones).
/// Bundle 218e: `5 Nov 2026` ('' when not set).
String joinedOffline218(Object? v) {
  final t = parseAdminTime216(v);
  if (t == null) return '';
  return '${dMMM216(t)} ${t.year}';
}

Future<void> showUserSheet216(BuildContext context, Map<String, dynamic> user) {
  final bloc = context.read<AdminBloc>();
  return showAdminSheet216<void>(
    context,
    builder: (sheet) => BlocProvider.value(
      value: bloc,
      child: _UserSheet(user: user),
    ),
  );
}

class _UserSheet extends StatefulWidget {
  const _UserSheet({required this.user});
  final Map<String, dynamic> user;

  @override
  State<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<_UserSheet> {
  late String _status = '${widget.user['status'] ?? 'active'}';
  String? _wifi;
  bool _wifiLoaded = false;

  String get _id => '${widget.user['id']}';
  String get _name => personName216(widget.user, fallback: _id);

  @override
  void initState() {
    super.initState();
    _loadWifi();
  }

  Future<void> _loadWifi() async {
    final p = await context.read<AdminBloc>().userNetworkPolicy(_id);
    if (!mounted) return;
    setState(() {
      _wifi = wifiRuleOf216(p, device: false);
      _wifiLoaded = true;
    });
  }

  Future<void> _setStatus(String to) async {
    if (to == _status) return;
    final label = userStatus216(to).text;
    final ok = await confirmAdmin216(
      context,
      title: 'Set $_name to $label?',
      body: switch (to) {
        'suspended' => '$_name can’t sign in until you set Active again.',
        'disabled' => '$_name’s account is closed. $_name can’t sign in.',
        _ => '$_name can use LinkUp again.',
      },
      yes: 'Set $label',
      danger: to != 'active',
    );
    if (!ok || !mounted) return;
    await context.read<AdminBloc>().setUserStatus(_id, to);
    if (mounted) setState(() => _status = to);
  }

  Future<void> _pickWifi() async {
    final r = await pickWifiRule216(context,
        current: _wifi, title: 'Wi-Fi rule for $_name', note: 'For every phone of this account');
    if (r == null || !mounted) return;
    final saved = await context
        .read<AdminBloc>()
        .updateUserNetworkPolicy(_id, wifiRadioPolicy: r.picked);
    if (saved != null && mounted) setState(() => _wifi = r.picked);
  }

  Future<void> _signOutAll() async {
    final ok = await confirmAdmin216(context,
        title: 'Sign out all phones?',
        body: '$_name must sign in again on every phone.',
        yes: 'Sign out',
        danger: true);
    if (!ok || !mounted) return;
    final bloc = context.read<AdminBloc>();
    final mine = [
      for (final s in bloc.state.sessions)
        if ('${s['user_id']}' == _id && s['active'] != false) '${s['id']}'
    ];
    for (final id in mine) {
      await bloc.revokeSession(id);
    }
    if (mounted) adminSnack216(context, '$_name is signed out on ${plural216(mine.length, 'phone')}.');
  }

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final role = context.read<AdminBloc>().adminRole;
    final canStatus = AdminPermissions.canManageUsers(role);
    final canWifi = AdminPermissions.canManageNetworkPolicy(role);
    final canSessions = AdminPermissions.canManageSessions(role);
    final u = widget.user;
    final n = (u['devices'] as num?)?.toInt() ?? 0;
    final online = ((u['online_devices'] as num?) ?? 0) > 0;
    final seen = age216(u['last_seen_at']);
    return Column(
      key: const ValueKey('a216_user_sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          ServerPersonAvatar216(
            name: _name,
            userId: _id,
            hasAvatar: u['has_avatar'] == true,
            radius: 28,
            admin: (u['admin_role'] ?? '').toString().isNotEmpty,
            online: online,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name, style: t.custom(18, FontWeight.w600, c.ink)),
              const SizedBox(height: 3),
              Text(
                  '@${u['username'] ?? ''} · ${n == 0 ? 'no phone' : plural216(n, 'phone')} · '
                  '${online ? 'online' : (seen.isEmpty ? 'offline' : 'last seen $seen')}',
                  style: t.cardSub),
              // Bundle 218e: this account came from an offline account.
              if (joinedOffline218(u['joined_offline_at']).isNotEmpty)
                Padding(
                  key: const ValueKey('a218_joined_offline'),
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(Icons.cloud_outlined, size: 13, color: c.blue),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                          'Joined from offline · ${joinedOffline218(u['joined_offline_at'])}',
                          overflow: TextOverflow.ellipsis,
                          style: t.custom(12, FontWeight.w500, c.blue)),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
        const AdminSection216('Status'),
        for (final s in const [
          ('active', 'Active', 'Can use LinkUp'),
          ('suspended', 'Suspended', 'Can’t sign in for now'),
          ('disabled', 'Off', 'Account closed'),
        ]) ...[
          AdminRadioCard216(
            key: ValueKey('a216_status_${s.$1}'),
            title: s.$2,
            subtitle: s.$3,
            selected: _status == s.$1,
            height: 54,
            sheet: true,
            onTap: canStatus ? () => _setStatus(s.$1) : null,
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        AdminListCard216([
          AdminRow216(
            key: const ValueKey('a216_wifi_rule'),
            leading: const AdminToneIcon216(Icons.wifi_rounded, A216Tone.teal),
            title: 'Wi-Fi rule',
            subtitle: _wifiLoaded ? wifiRuleLabel216(_wifi) : '…',
            enabled: canWifi,
            onTap: _pickWifi,
          ),
          AdminRow216(
            key: const ValueKey('a216_signout_all'),
            leading: const AdminToneIcon216(Icons.logout_rounded, A216Tone.red),
            title: 'Sign out all phones',
            subtitle: '$_name must sign in again',
            enabled: canSessions,
            onTap: _signOutAll,
          ),
        ], shadow: false),
        if (!canStatus && !canWifi) ...[
          const SizedBox(height: 10),
          Text('You can only look.', textAlign: TextAlign.center, style: t.note),
        ],
      ],
    );
  }
}
