import 'package:locallink/core/utils/phone_label_255.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 216 (page 19): Recovery — people moving to a new phone.
class AdminRecoveryScreen extends StatefulWidget {
  const AdminRecoveryScreen({super.key});

  @override
  State<AdminRecoveryScreen> createState() => _AdminRecoveryScreenState();
}

class _AdminRecoveryScreenState extends State<AdminRecoveryScreen> {
  /// Code just given, per request id (shown in the code card).
  final Map<String, String> _codes = {};

  Future<void> _approve(Map<String, dynamic> r, {bool reissue = false}) async {
    final result =
        await context.read<AdminBloc>().approve('${r['id']}', reissue: reissue);
    if (result == null || !mounted) return;
    final code = result['recovery_credential']?.toString() ?? '';
    if (code.isEmpty) {
      adminSnack216(context, L.t.noOneTimeCodeWasReturned);
      return;
    }
    setState(() => _codes['${r['id']}'] = code);
  }

  Future<void> _reject(Map<String, dynamic> r) async {
    final ctrl = TextEditingController();
    final reason = await showAdminSheet216<String>(context, builder: (sheet) {
      final t = A216Text.of(sheet);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(L.t.rejectThisRequest, style: t.sheetTitle),
        const SizedBox(height: 6),
        Text(L.t.canAskAgainLater(personName216(r, fallback: 'They')), style: t.cardSub),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('a216_reject_reason'),
          controller: ctrl,
          maxLength: 256,
          decoration: InputDecoration(
            isDense: true,
            labelText: L.t.reasonOptional,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 6),
        AdminButton216(L.t.reject,
            key: const ValueKey('a216_reject_yes'),
            kind: A216ButtonKind.danger,
            onTap: () => Navigator.of(sheet).pop(ctrl.text.trim())),
      ]);
    });
    ctrl.dispose();
    if (reason == null || !mounted) return;
    await context.read<AdminBloc>().reject('${r['id']}', reason);
  }

  static String endsIn(Object? v) {
    final t = parseAdminTime216(v);
    if (t == null) return '';
    final left = t.difference(adminNow216());
    if (left.isNegative) return 'ended';
    if (left.inHours >= 1) return L.t.endsInH(left.inHours);
    return L.t.endsInMin(left.inMinutes.clamp(1, 59));
  }

  Widget _codeCard(Map<String, dynamic> r, String code, bool canManage) {
    final c = A216.colors(context);
    final t = A216Text(c);
    return AdminCard216(
      key: ValueKey('a216_code_${r['id']}'),
      fill: const Color(0xFFEFF4FF),
      border: const Color(0xFFC7D7FE),
      shadow: false,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(L.t.oneTimeCodeFor(personName216(r, fallback: 'them')),
            style: t.custom(13, FontWeight.w600, const Color(0xFF1D3A8A))),
        const SizedBox(height: 10),
        SelectableText(groupCode216(code), textAlign: TextAlign.center, style: t.bigCode),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: AdminButton216(L.t.copy,
                key: ValueKey('a216_copy_${r['id']}'),
                icon: Icons.copy_rounded,
                kind: A216ButtonKind.outline,
                height: 34,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (mounted) adminSnack216(context, L.t.codeCopied);
                }),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AdminButton216(L.t.newCode,
                key: ValueKey('a216_new_code_${r['id']}'),
                kind: A216ButtonKind.outline,
                height: 34,
                onTap: canManage ? () => _approve(r, reissue: true) : null),
          ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'Recovery',
      module: 'Recovery',
      subtitle: (_) => L.t.peopleMovingToANewPhone,
      builder: (context, state) {
        final c = A216.colors(context);
        final t = A216Text(c);
        final canManage =
            AdminPermissions.canManageRecovery(context.read<AdminBloc>().adminRole);
        final waiting = [for (final r in state.recoveries) if ('${r['status']}' == 'pending') r];
        final earlier = [for (final r in state.recoveries) if ('${r['status']}' != 'pending') r];
        final out = <Widget>[];
        if (state.loading && state.recoveries.isEmpty) out.add(const AdminLoading216());
        for (final r in waiting) {
          final name = personName216(r, fallback: L.t.someone);
          out.add(AdminCard216(
            key: ValueKey('a216_request_${r['id']}'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                ServerPersonAvatar216(
                    name: name,
                    userId: '${r['user_id'] ?? ''}',
                    hasAvatar: r['has_avatar'] == true,
                    radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: t.custom(15, FontWeight.w600, c.ink)),
                    const SizedBox(height: 3),
                    Text(L.t.newPhone(phoneTitle255('${r['target_device_name'] ?? ''}', name, fallback: 'not named')), style: t.cardSub), // Bundle 276
                  ]),
                ),
                AdminTag216(L.t.waiting, A216Tone.orange, dot: true),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.schedule_rounded, size: 14, color: c.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(L.t.asked(whenSub216(r['created_at']), endsIn(r['expires_at'])),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.cardSub),
                ),
              ]),
              if (canManage) ...[
                const SizedBox(height: 14),
                Row(children: [
                  AdminButton216(L.t.approveAndGiveCode,
                      key: ValueKey('a216_approve_${r['id']}'),
                      width: 196,
                      height: 40,
                      onTap: () => _approve(r)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AdminButton216(L.t.reject,
                        key: ValueKey('a216_reject_${r['id']}'),
                        kind: A216ButtonKind.outline,
                        height: 40,
                        onTap: () => _reject(r)),
                  ),
                ]),
              ],
            ]),
          ));
          final code = _codes['${r['id']}'];
          if (code != null) {
            out
              ..add(const SizedBox(height: 10))
              ..add(_codeCard(r, code, canManage));
          }
          out.add(const SizedBox(height: 12));
        }
        // Codes given for requests that moved to "approved".
        for (final r in earlier) {
          final code = _codes['${r['id']}'];
          if (code == null) continue;
          out
            ..add(_codeCard(r, code, canManage))
            ..add(const SizedBox(height: 12));
        }
        if (waiting.isEmpty && !(state.loading && state.recoveries.isEmpty)) {
          out.add(AdminEmptyState216(
              icon: Icons.restore_rounded,
              tone: A216Tone.orange,
              title: L.t.noOneIsAsking,
              body: L.t.whenSomeoneMovesToANew));
        }
        if (earlier.isNotEmpty) {
          out
            ..add(AdminSection216(L.t.earlier))
            ..add(AdminListCard216([
              for (final r in earlier)
                AdminRow216(
                  key: ValueKey('a216_earlier_${r['id']}'),
                  height: 62,
                  leading: ServerPersonAvatar216(
                      name: personName216(r, fallback: '?'),
                      userId: '${r['user_id'] ?? ''}',
                      hasAvatar: r['has_avatar'] == true),
                  title: personName216(r, fallback: L.t.someone),
                  subtitle:
                      L.t.newPhone2(phoneTitle255('${r['target_device_name'] ?? ''}', personName216(r), fallback: 'not named'), whenSub216(r['created_at'])), // Bundle 276
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: '${r['status']}' == 'rejected'
                        ? AdminTag216(L.t.rejected, A216Tone.red)
                        : AdminTag216(
                            '${r['status']}' == 'approved' || '${r['status']}' == 'completed'
                                ? L.t.approved
                                : level216(r['status']),
                            A216Tone.green),
                  ),
                  onTap: canManage && '${r['status']}' == 'approved'
                      ? () => _approve(r, reissue: true)
                      : null,
                ),
            ]));
        }
        return out;
      },
    );
  }
}
