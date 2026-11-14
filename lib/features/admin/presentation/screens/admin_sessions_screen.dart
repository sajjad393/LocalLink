import 'package:locallink/core/utils/phone_label_255.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/features/admin/data/actions/admin_action_offline.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 216 (page 15): who is signed in, on which phone.
class AdminSessionsScreen extends StatelessWidget {
  const AdminSessionsScreen({super.key, this.thisDeviceId});

  /// This phone's device id ('This phone' tag).
  final String? thisDeviceId;

  static String since(Object? v) {
    final t = parseAdminTime216(v);
    if (t == null) return '';
    final n = adminNow216();
    if (t.year == n.year && t.month == n.month && t.day == n.day) return 'today';
    return dMMM216(t);
  }

  Future<void> _signOut(BuildContext context, String id, {required bool admin}) async {
    final ok = await confirmAdmin216(context,
        title: admin ? L.t.signOutThisAdmin : L.t.signOutThisPhone,
        body: admin ? L.t.thisAdminSessionEndsNow : L.t.itMustSignInAgain,
        yes: L.t.signOut,
        danger: true);
    if (!ok || !context.mounted) return;
    final bloc = context.read<AdminBloc>();
    final row = admin
        ? null
        : bloc.state.sessions.cast<Map<String, dynamic>?>().firstWhere(
            (s) => '${s?['id']}' == id, orElse: () => null);
    await (admin ? bloc.revokeAdminSession(id) : bloc.revokeSession(id));
    // Bundle 220: no server -> a sign-out card for that phone.
    final device = '${row?['device_id'] ?? ''}';
    if (row != null && device.isNotEmpty) {
      final note = await AdminActionOffline.ifOffline(
          action: 'sign_out',
          userId: '${row['user_id'] ?? ''}',
          label: personName216(row, fallback: '${row['username'] ?? ''}'),
          devices: [device]);
      if (note != null && context.mounted) adminSnack216(context, note);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'Sessions',
      module: 'Sessions',
      subtitle: (_) => L.t.whoIsSignedInOnWhich,
      builder: (context, state) {
        final c = A216.colors(context);
        final t = A216Text(c);
        final canManage = AdminPermissions.canManageSessions(context.read<AdminBloc>().adminRole);
        final people = [for (final s in state.sessions) if (s['active'] != false) s];
        final admins = [for (final s in state.adminSessions) if (s['active'] != false) s];
        final usersByName = {
          for (final u in state.users) '${u['username']}': u,
        };
        Widget nobody() => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(L.t.nobodySignedIn, textAlign: TextAlign.center, style: t.note),
            );
        Widget signOut(String id, {required bool admin}) => AdminPillButton216(
              L.t.signOut,
              A216Tone.red,
              canManage ? () => _signOut(context, id, admin: admin) : null,
              key: ValueKey('a216_signout_$id'),
            );
        return [
          if (state.loading && people.isEmpty && admins.isEmpty) const AdminLoading216(),
          AdminSection216(L.t.peopleSignedIn,
              right: '${people.length}', rightColor: c.blue, top: 4),
          if (people.isEmpty)
            nobody()
          else
            AdminListCard216([
              for (final s in people)
                AdminRow216(
                  key: ValueKey('a216_session_${s['id']}'),
                  height: 64,
                  leading: ServerPersonAvatar216(
                    name: personName216(s, fallback: '?'),
                    userId: '${s['user_id'] ?? ''}',
                    deviceId: '${s['device_id'] ?? ''}',
                    hasAvatar: usersByName['${s['username']}']?['has_avatar'] == true,
                  ),
                  title: personName216(s, fallback: '${s['user_id'] ?? ''}'),
                  subtitle: L.t.since2(phoneTitle255('${s['device_name'] ?? ''}', personName216(s)), since(s['created_at'])), // Bundle 276
                  trailing: thisDeviceId != null && '${s['device_id']}' == thisDeviceId
                      ? Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: AdminTag216(L.t.thisPhone, A216Tone.blue))
                      : signOut('${s['id']}', admin: false),
                ),
            ]),
          AdminSection216(L.t.adminsSignedIn),
          if (admins.isEmpty)
            nobody()
          else
            AdminListCard216([
              for (final s in admins)
                () {
                  final known = usersByName['${s['username']}'];
                  return AdminRow216(
                    key: ValueKey('a216_admin_session_${s['id']}'),
                    height: 64,
                    leading: known != null
                        ? ServerPersonAvatar216(
                            name: personName216(known, fallback: '${s['username']}'),
                            userId: '${known['id']}',
                            hasAvatar: known['has_avatar'] == true,
                          )
                        : const AdminToneIcon216(Icons.vpn_key_outlined, A216Tone.grey),
                    title: '${s['username'] ?? 'admin'} · ${level216(s['role'])}',
                    subtitle:
                        L.t.sinceEnds(whenSub216(s['created_at']), parseAdminTime216(s['expires_at']) == null ? '—' : dMMM216(parseAdminTime216(s['expires_at'])!)),
                    trailing: s['current'] == true
                        ? Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: AdminTag216(L.t.thisOne, A216Tone.blue))
                        : signOut('${s['id']}', admin: true),
                  );
                }(),
            ]),
        ];
      },
    );
  }
}
