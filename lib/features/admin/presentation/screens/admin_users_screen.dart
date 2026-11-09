import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/features/admin/data/actions/admin_action_offline.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/services/admin_offline_users_222.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/core/widgets/admin_crown.dart' show AdminCrownRoom;
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
  String _filter = 'All'; // Bundle 222: by name (the "Not on server" chip comes and goes)
  bool _showHidden238 = false; // Bundle 238: "Show hidden (N)"

  /// Bundle 222: extra row height (and photo shift) for the crown on a
  /// 20 px photo whose row already leaves 12 px above it, plus 2 px air.
  static final double _crownExtra222 = AdminCrownRoom.extraFor(20, already: 12) + 2;

  static bool _isAdmin(Map<String, dynamic> u) => (u['admin_role'] ?? '').toString().isNotEmpty;

  bool _match(Map<String, dynamic> u) {
    final status = '${u['status'] ?? 'active'}';
    final ok = switch (_filter) {
      'Admins' => _isAdmin(u),
      'Active' => status == 'active',
      'Stopped' => status == 'suspended' || status == 'disabled',
      'Not on server' => false,
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
  void initState() {
    super.initState();
    unawaited(AdminOfflineUsers222.refresh()); // Bundle 222
  }

  /// Bundle 222 (U-1): offline accounts seen nearby, on All / Not on server.
  List<OfflineUser222> _localRows(List<OfflineUser222> all) {
    if (_filter != 'All' && _filter != 'Not on server') return const [];
    final q = _q.trim().toLowerCase().replaceFirst('@', '');
    if (q.isEmpty) return all;
    return all.where((u) => '${u.name} ${u.username}'.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<OfflineUser222>>(
      valueListenable: AdminOfflineUsers222.rows,
      builder: (context, local, _) => ValueListenableBuilder<List<OfflineUser222>>(
        valueListenable: AdminOfflineUsers222.hidden,
        builder: (context, gone, _) => _build(context, local, gone),
      ),
    );
  }

  Widget _build(BuildContext context, List<OfflineUser222> local, [List<OfflineUser222> gone = const []]) {
    // Mock U-1: All, Admins, Active, Not on server, (Stopped).
    final filters = [..._filters.take(3), if (local.isNotEmpty) 'Not on server', ..._filters.skip(3)];
    if (!filters.contains(_filter)) _filter = 'All';
    return AdminToolPage216(
      title: 'Users',
      module: 'Users',
      worksOffline: true,
      subtitle: (s) => [
        people216(s.users.length + local.length),
        plural216(s.users.where(_isAdmin).length, 'admin'),
        if (local.isNotEmpty) '${local.length} not on server',
      ].join(' · '),
      builder: (context, state) {
        final rows = state.users.where(_match).toList();
        final mine = _localRows(local);
        // Bundle 238: old offline rows (30 days / cleared phone), only on
        // the switch; the count follows the filter and the search.
        final hiddenRows = _localRows(gone);
        final shownHidden = _showHidden238 ? hiddenRows : const <OfflineUser222>[];
        return [
          AdminSearch216(
            hint: 'Search name or @username',
            fieldKey: const ValueKey('a216_users_search'),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 10),
          AdminChips216(
            items: filters,
            selected: filters.indexOf(_filter),
            keys: [for (final f in filters) ValueKey('a216_users_filter_${f.toLowerCase().replaceAll(' ', '_')}')],
            onSelected: (i) => setState(() => _filter = filters[i]),
          ),
          const SizedBox(height: 12),
          if (state.loading && state.users.isEmpty && mine.isEmpty)
            const AdminLoading216()
          else if (rows.isEmpty && mine.isEmpty && shownHidden.isEmpty)
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
                  // Bundle 222 (C-1): an admin row is taller and its photo
                  // sits lower, so the crown stays inside the row and card.
                  height: _isAdmin(u) ? 64 + _crownExtra222 : 64,
                  leading: Padding(
                    padding: EdgeInsets.only(top: _isAdmin(u) ? _crownExtra222 : 0),
                    child: ServerPersonAvatar216(
                      name: personName216(u, fallback: '?'),
                      userId: '${u['id']}',
                      hasAvatar: u['has_avatar'] == true,
                      admin: _isAdmin(u),
                      grey: '${u['status'] ?? 'active'}' != 'active',
                      online: ((u['online_devices'] as num?) ?? 0) > 0,
                    ),
                  ),
                  title: personName216(u, fallback: '${u['id']}'),
                  subtitle: joinedRecently222(u) ? '${sub(u)} · Joined from offline' : sub(u),
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: AdminTag216(userStatus216(u['status']).text,
                        userStatus216(u['status']).tone,
                        dot: true),
                  ),
                  onTap: () => showUserSheet216(context, u),
                ),
              // Bundle 222 (U-1): offline accounts seen nearby.
              for (final u in mine)
                AdminRow216(
                  key: ValueKey('a222_offline_user_${u.userId}'),
                  height: 64,
                  leading: ServerPersonAvatar216(name: u.name, userId: u.userId, hasAvatar: false),
                  title: u.name,
                  subtitle: offlineSub222(u),
                  trailing: const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: AdminTag216('Offline account', A216Tone.grey),
                  ),
                  onTap: () => showOfflineUserSheet222(context, u),
                ),
              // Bundle 238: hidden offline rows, only when switched on.
              for (final u in shownHidden)
                AdminRow216(
                  key: ValueKey('a238_hidden_user_${u.userId}'),
                  height: 64,
                  leading: ServerPersonAvatar216(name: u.name, userId: u.userId, hasAvatar: false, grey: true),
                  title: u.name,
                  subtitle: hiddenSub238(u),
                  trailing: const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: AdminTag216('Hidden', A216Tone.grey),
                  ),
                  onTap: () => showOfflineUserSheet222(context, u),
                ),
            ]),
          if (hiddenRows.isNotEmpty) ...[
            const SizedBox(height: 8),
            ShowHiddenRow238(
              count: hiddenRows.length,
              value: _showHidden238,
              onChanged: (v) => setState(() => _showHidden238 = v),
            ),
          ],
        ];
      },
    );
  }
}

/// Bundle 238: "Not seen for 30+ days · router · 41 days" - why it hides.
String hiddenSub238(OfflineUser222 u) =>
    ['Not seen for 30+ days', u.link, offlineShort222(u.seenAt)].where((x) => x.isNotEmpty).join(' · ');

/// Bundle 238 (mock 238): the switch under the list. Old offline rows
/// (not seen for 30 days, or a cleared phone that joined again) stay in the
/// data; only the list hides them.
class ShowHiddenRow238 extends StatelessWidget {
  final int count;
  final bool value;
  final ValueChanged<bool> onChanged;
  const ShowHiddenRow238({super.key, required this.count, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('a238_users_show_hidden'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Icon(Icons.visibility_off_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Show hidden ($count)', style: theme.textTheme.bodyMedium),
                    Text('Offline accounts not seen for 30 days',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// `2 h`, `5 min`, `1 day` (mock U-1).
String offlineShort222(String at, {DateTime? now}) {
  final t = DateTime.tryParse(at);
  if (t == null) return '';
  final d = (now ?? DateTime.now()).toUtc().difference(t.toUtc());
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours} h';
  return plural216(d.inDays, 'day');
}

String offlineSub222(OfflineUser222 u) =>
    ['Not on server yet', u.link, offlineShort222(u.seenAt)].where((x) => x.isNotEmpty).join(' · ');

/// Bundle 222: a server row that came from an offline account shows a
/// small note for 7 days (server field `joined_offline_at`, 218e).
bool joinedRecently222(Map<String, dynamic> u, {DateTime? now}) {
  final t = DateTime.tryParse('${u['joined_offline_at'] ?? ''}');
  if (t == null) return false;
  return (now ?? DateTime.now()).toUtc().difference(t.toUtc()) <= AdminOfflineUsers222.joinedNote;
}

/// Bundle 222 (U-2): an offline account's sheet. Block and Sign out go as
/// 220 admin action cards (Pending until done, no server needed). More
/// actions after she joins the server.
Future<void> showOfflineUserSheet222(BuildContext context, OfflineUser222 u, {AdminActionService? service}) =>
    showAdminSheet216<void>(context, builder: (sheet) => _OfflineSheet222(user: u, service: service));

class _OfflineSheet222 extends StatelessWidget {
  const _OfflineSheet222({required this.user, this.service});
  final OfflineUser222 user;
  final AdminActionService? service;

  Future<void> _act(BuildContext context, String action) async {
    final verb = action == 'block' ? 'Block' : 'Sign out';
    final ok = await confirmAdmin216(
      context,
      title: '$verb ${user.name}?',
      body: 'It goes to her phone by card, over any link. Pending until it is done.',
      yes: verb,
      danger: action == 'block',
    );
    if (!ok || !context.mounted) return;
    final s = service ?? AdminActionService.instance;
    var note = 'Admin actions are not ready on this phone';
    if (s != null) {
      try {
        await s.make(
          action: action,
          targetUserId: user.userId,
          label: user.name,
          targetDevices: [if (user.deviceId.isNotEmpty) user.deviceId],
        );
        note = 'Sent to all phones · Pending until it is done';
      } on StateError catch (e) {
        note = e.message;
      } catch (_) {
        note = 'Could not send. Try again';
      }
    }
    if (context.mounted) adminSnack216(context, note);
  }

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final seen = [user.link, offlineShort222(user.seenAt)].where((x) => x.isNotEmpty).join(' · ');
    Widget kv(String k, String v, String key) => Padding(
          key: ValueKey(key),
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Text(k, style: t.custom(14, FontWeight.w400, c.ink2)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(v,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: t.custom(14, FontWeight.w500, c.ink))),
          ]),
        );
    return Column(
      key: const ValueKey('a222_offline_sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: ServerPersonAvatar216(name: user.name, userId: user.userId, hasAvatar: false, radius: 28)),
        const SizedBox(height: 10),
        Text(user.name, textAlign: TextAlign.center, style: t.custom(18, FontWeight.w600, c.ink)),
        if (user.username.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('@${user.username} (may change if taken)', textAlign: TextAlign.center, style: t.cardSub),
          ),
        const SizedBox(height: 12),
        kv('Status', 'Offline account · not on server yet', 'a222_os_status'),
        if (user.phoneModel.isNotEmpty) kv('Phone', user.phoneModel, 'a222_os_phone'),
        if (seen.isNotEmpty) kv('Seen', seen, 'a222_os_seen'),
        kv('Server', user.carried ? 'Waiting · carried by this phone' : 'Waiting to join the server', 'a222_os_server'),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: AdminButton216('Block',
                  key: const ValueKey('a222_os_block'),
                  kind: A216ButtonKind.tonal,
                  onTap: () => _act(context, 'block'))),
          const SizedBox(width: 10),
          Expanded(
              child: AdminButton216('Sign out',
                  key: const ValueKey('a222_os_signout'),
                  kind: A216ButtonKind.tonal,
                  onTap: () => _act(context, 'sign_out'))),
        ]),
        const SizedBox(height: 12),
        Text('Actions go to her phone by card (Pending until done). More actions after she joins the server.',
            style: t.cardSub),
      ],
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
    // Bundle 220: no server -> Off / Active / Block go as a card to all phones.
    final note = await AdminActionOffline.ifOffline(
      action: switch (to) { 'disabled' => 'off', 'suspended' => 'block', _ => 'active' },
      userId: _id,
      label: _name,
    );
    if (note != null && mounted) adminSnack216(context, note);
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
    // Bundle 220: no server -> the Wi-Fi rule goes as a card to all phones.
    final note = await AdminActionOffline.ifOffline(
      action: 'wifi_rule',
      userId: _id,
      label: _name,
      detail: {'level': 'user', 'wifi_radio_policy': r.picked ?? ''},
      words: r.picked ?? 'no rule',
    );
    if (note != null && mounted) adminSnack216(context, note);
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
    // Bundle 220: no server -> a sign-out card for each phone.
    final phones = <String>{
      for (final s in bloc.state.sessions)
        if ('${s['user_id']}' == _id && '${s['device_id'] ?? ''}'.isNotEmpty) '${s['device_id']}'
    };
    String? note;
    for (final d in phones.isEmpty ? const <String>[''] : phones.toList()) {
      note = await AdminActionOffline.ifOffline(
          action: 'sign_out', userId: _id, label: _name, devices: [if (d.isNotEmpty) d]);
    }
    if (mounted) {
      adminSnack216(context, note ?? '$_name is signed out on ${plural216(mine.length, 'phone')}.');
    }
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
