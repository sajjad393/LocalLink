import 'package:flutter/material.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_list_page.dart';
import 'package:locallink/l10n/l10n.dart';

/// "12 Nov, 8:49 PM" style short time.
String blockWhen(String iso) {
  final at = DateTime.tryParse(iso)?.toLocal();
  if (at == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final m = at.minute.toString().padLeft(2, '0');
  return '${at.day} ${L.en(months[at.month - 1])}, $h:$m ${at.hour < 12 ? 'AM' : 'PM'}';
}

/// Bundle 212 (E4, mock page 6): "Blocked by admin".
class AdminBlockedListScreen extends StatefulWidget {
  const AdminBlockedListScreen({super.key, required this.service});

  final AdminBlockService? service;

  @override
  State<AdminBlockedListScreen> createState() => _AdminBlockedListScreenState();
}

class _AdminBlockedListScreenState extends State<AdminBlockedListScreen> {
  String _query = '';
  int _shown = kAdminListPage;

  // Bundle 216 (page 9): 216 look; keys and texts kept (212e).
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AdminBlockBook.instance,
        builder: (context, _) {
          final all = [
            for (final e in widget.service?.entries ?? const <AdminBlockEntry>[])
              if (e.record.isBlock) e,
          ];
          final page = adminListPage<AdminBlockEntry>(all,
              query: _query,
              shown: _shown,
              keys: (e) => [e.record.targetName, e.record.targetUserId]);
          return AdminPage216(
            title: 'Blocked by admin',
            subtitle: L.t.blockedOnEveryLinkupPhoneIt(all.length),
            children: [
              if (all.length > kAdminListSearchFrom) ...[
                AdminSearch216(
                  hint: L.t.searchName,
                  fieldKey: const ValueKey('admin_blocked_search'),
                  onChanged: (q) => setState(() {
                    _query = q;
                    _shown = kAdminListPage;
                  }),
                ),
                const SizedBox(height: 12),
              ],
              if (all.isEmpty)
                AdminEmptyState216(
                    icon: Icons.verified_user_outlined,
                    tone: A216Tone.green,
                    title: L.t.noOneIsBlockedByAdmin,
                    body: L.t.peopleYouBlockHereAreStopped)
              else
                AdminListCard216([for (final e in page.visible) _row(e)]),
              const SizedBox(height: 6),
              AdminListMoreButton(
                shown: _shown,
                matched: page.matched,
                onPressed: () => setState(() => _shown += kAdminListPage),
              ),
              const SizedBox(height: 8),
              AdminBanner216(A216BannerKind.info, L.t.onlyForThisPhone,
                  body: L.t.useBlockedOnThisPhoneIt),
            ],
          );
        },
      );

  AdminRow216 _row(AdminBlockEntry e) {
    final r = e.record;
    final target = BlockTarget(
        userId: r.targetUserId,
        deviceIds: r.targetDevices,
        name: r.targetName.isEmpty ? r.targetUserId : r.targetName);
    final by = r.signer == 'server'
        ? L.t.webPanel
        : (e.source == 'me' ? 'you' : (r.by.isEmpty ? 'admin' : r.by));
    final at = parseAdminTime216(r.at);
    final status = [
      if (e.source == 'me') L.t.reachedPhone(e.reached, e.reached == 1 ? '' : 's'),
      e.serverDone ? L.t.onServer : L.t.notOnServerYet,
    ].join(' · ');
    final color = e.serverDone ? const Color(0xFF12805C) : const Color(0xFFB54708);
    return AdminRow216(
      key: ValueKey('admin_blocked_${r.targetUserId}'),
      height: 80,
      leading: AdminPersonAvatar216(
        name: target.name,
        userId: target.userId,
        deviceId: target.deviceIds.isEmpty ? null : target.deviceIds.first,
        blocked: true,
      ),
      title: target.name,
      subtitle: '${L.t.byWho304(by)} · ${at == null ? '' : whenSub216(at)}',
      subtitleWidget: Row(children: [
        Container(
            width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: A216Text.of(context).custom(12, FontWeight.w600, color)),
        ),
      ]),
      trailing: AdminPillButton216(
        L.t.unblock,
        A216Tone.grey,
        () async {
          await runAdminBlock(context, service: widget.service, target: target, block: false);
          if (mounted) setState(() {});
        },
        key: ValueKey('admin_unblock_${r.targetUserId}'),
      ),
    );
  }
}
