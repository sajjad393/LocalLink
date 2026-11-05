import 'package:flutter/material.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_list_page.dart';

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
  return '${at.day} ${months[at.month - 1]}, $h:$m ${at.hour < 12 ? 'AM' : 'PM'}';
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

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF5F6F8),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: const Text('Blocked by admin',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: ListenableBuilder(
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
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (all.length > kAdminListSearchFrom)
                  AdminListSearch(
                    hint: 'Search name',
                    onChanged: (q) => setState(() {
                      _query = q;
                      _shown = kAdminListPage;
                    }),
                  ),
                Text('${all.length} blocked · applies on every LinkUp phone it reaches',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF5B6472))),
                const SizedBox(height: 10),
                if (all.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: Text('No one is blocked by admin')),
                  ),
                for (final e in page.visible) _card(e),
                AdminListMoreButton(
                  shown: _shown,
                  matched: page.matched,
                  onPressed: () => setState(() => _shown += kAdminListPage),
                ),
              ],
            );
          },
        ),
      );

  Widget _card(AdminBlockEntry e) {
    final r = e.record;
    final target = BlockTarget(
        userId: r.targetUserId,
        deviceIds: r.targetDevices,
        name: r.targetName.isEmpty ? r.targetUserId : r.targetName);
    final by = r.signer == 'server' ? 'web panel' : (r.by.isEmpty ? 'admin' : r.by);
    return Container(
      key: ValueKey('admin_blocked_${r.targetUserId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E6EC)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFFE5E7EB),
          child: Text(target.initials,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(target.name,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text('By $by · ${blockWhen(r.at)}',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6472))),
            const SizedBox(height: 2),
            Text(
                [
                  if (e.source == 'me')
                    'Reached ${e.reached} phone${e.reached == 1 ? '' : 's'}',
                  e.serverDone ? 'Server: done' : 'Server: waiting',
                ].join(' · '),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: e.serverDone
                        ? const Color(0xFF15803D)
                        : const Color(0xFF9A5B06))),
          ]),
        ),
        TextButton(
          key: ValueKey('admin_unblock_${r.targetUserId}'),
          onPressed: () async {
            await runAdminBlock(context,
                service: widget.service, target: target, block: false);
            if (mounted) setState(() {});
          },
          child: const Text('Unblock',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
