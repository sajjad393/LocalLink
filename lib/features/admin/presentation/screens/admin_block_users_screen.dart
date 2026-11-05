import 'package:flutter/material.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_list_page.dart';

/// One person the admin can pick (E2).
class BlockCandidate {
  final BlockTarget target;
  final bool nearby;

  const BlockCandidate({required this.target, required this.nearby});
}

/// "seen 2 days ago" from an ISO time ('' when unknown).
String seenLabel(String iso, {DateTime? now}) {
  final at = DateTime.tryParse(iso);
  if (at == null) return '';
  final d = (now ?? DateTime.now()).toUtc().difference(at.toUtc());
  if (d.inMinutes < 2) return 'seen just now';
  if (d.inHours < 1) return 'seen ${d.inMinutes} min ago';
  if (d.inDays < 1) return 'seen ${d.inHours} h ago';
  if (d.inDays == 1) return 'seen yesterday';
  return 'seen ${d.inDays} days ago';
}

/// Everyone this phone has seen (saved profiles + phones) and who is
/// nearby now. Never this phone's own account.
Future<List<BlockCandidate>> loadBlockCandidates(LocalStore store) async {
  final self = {store.accountId ?? '', store.deviceId ?? ''}..remove('');
  final devices = <String, Device>{
    for (final d in await store.localDevices()) d.id: d,
  };
  bool near(Device? d) =>
      d != null && (d.wifiDirectConnected || d.meshAvailable || d.lanAvailable);
  final out = <String, BlockCandidate>{};
  final usedDevices = <String>{};
  for (final p in await store.directoryProfiles()) {
    final userId = p['user_id']?.toString() ?? '';
    final deviceId = p['device_id']?.toString() ?? '';
    if (userId.isEmpty || self.contains(userId) || self.contains(deviceId)) {
      continue;
    }
    final d = devices[deviceId];
    if (deviceId.isNotEmpty) usedDevices.add(deviceId);
    final display = p['display_name']?.toString().trim() ?? '';
    final username = p['username']?.toString().trim() ?? '';
    final name = display.isNotEmpty
        ? display
        : (username.isNotEmpty ? username : (d?.name ?? userId));
    out[userId] = BlockCandidate(
      nearby: near(d),
      target: BlockTarget(
        userId: userId,
        deviceIds: [if (deviceId.isNotEmpty) deviceId],
        name: name,
        username: username,
        seen: near(d)
            ? 'nearby now'
            : seenLabel(d?.presenceLocalAt.isNotEmpty == true
                ? d!.presenceLocalAt
                : (p['synced_at'] ?? p['updated_at'] ?? '').toString()),
      ),
    );
  }
  for (final d in devices.values) {
    if (d.current || self.contains(d.id) || usedDevices.contains(d.id)) continue;
    out[d.id] = BlockCandidate(
      nearby: near(d),
      target: BlockTarget(
        userId: d.id,
        deviceIds: [d.id],
        name: d.name.trim().isEmpty ? d.id : d.name,
        seen: near(d) ? 'nearby now' : seenLabel(d.presenceLocalAt),
      ),
    );
  }
  final list = out.values.toList()
    ..sort((a, b) =>
        a.target.name.toLowerCase().compareTo(b.target.name.toLowerCase()));
  return list;
}

/// Bundle 212 (E2, mock page 2): "Block or unblock a user".
class AdminBlockUsersScreen extends StatefulWidget {
  const AdminBlockUsersScreen(
      {super.key, required this.load, required this.service});

  final Future<List<BlockCandidate>> Function() load;
  final AdminBlockService? service;

  @override
  State<AdminBlockUsersScreen> createState() => _AdminBlockUsersScreenState();
}

class _AdminBlockUsersScreenState extends State<AdminBlockUsersScreen> {
  List<BlockCandidate> _all = const [];
  bool _loading = true;
  String _query = '';
  int _shown = kAdminListPage;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final list = await widget.load();
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = adminListPage<BlockCandidate>(_all,
        query: _query,
        shown: _shown,
        keys: (c) => [c.target.name, c.target.username, '@${c.target.username}']);
    final nearby = [for (final c in page.visible) if (c.nearby) c];
    final seen = [for (final c in page.visible) if (!c.nearby) c];
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Block or unblock a user',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListenableBuilder(
        listenable: AdminBlockBook.instance,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            AdminListSearch(
              key: const ValueKey('admin_block_search'),
              hint: 'Search name or @username',
              onChanged: (q) => setState(() {
                _query = q;
                _shown = kAdminListPage;
              }),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (page.matched == 0)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No one found')),
              ),
            if (nearby.isNotEmpty) ...[
              _label('NEARBY NOW'),
              _card(nearby),
            ],
            if (seen.isNotEmpty) ...[
              _label('SEEN BEFORE'),
              _card(seen),
            ],
            AdminListMoreButton(
              shown: _shown,
              matched: page.matched,
              onPressed: () => setState(() => _shown += kAdminListPage),
            ),
            const SizedBox(height: 10),
            const Text(
              'Only people this phone has seen are listed. Others can be blocked from the web panel.',
              style: TextStyle(fontSize: 12, color: Color(0xFF5B6472)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: Color(0xFF5B6472))),
      );

  Widget _card(List<BlockCandidate> list) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E6EC)),
        ),
        child: Column(children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFE2E6EC)),
            _row(list[i]),
          ],
        ]),
      );

  Widget _row(BlockCandidate c) {
    final t = c.target;
    final entry = widget.service?.entryFor(t.userId) ??
        (t.deviceIds.isEmpty ? null : widget.service?.entryFor(t.deviceIds.first));
    final blocked = entry?.record.isBlock == true ||
        AdminBlockBook.instance.isBlocked(t.userId) ||
        t.deviceIds.any(AdminBlockBook.instance.isBlocked);
    final waiting = blocked && entry != null && !entry.serverDone;
    final chip = blocked
        ? (waiting ? 'Blocked · server later' : 'Blocked by admin')
        : 'Active';
    final chipFg = blocked ? kBlockRed : const Color(0xFF15803D);
    final chipBg = blocked ? kBlockRedTint : const Color(0xFFE3F6EA);
    return InkWell(
      key: ValueKey('admin_block_row_${t.userId}'),
      onTap: () async {
        final done = await runAdminBlock(context,
            service: widget.service, target: t, block: !blocked);
        if (done && mounted) setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: blocked
                ? const Color(0xFFE5E7EB)
                : const Color(0xFF7C5CDB).withValues(alpha: 0.14),
            child: Text(t.initials,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: blocked
                        ? const Color(0xFF6B7280)
                        : const Color(0xFF5B3FB8))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(
                  [
                    if (t.username.isNotEmpty) '@${t.username}',
                    if (t.seen.isNotEmpty) t.seen,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6472))),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: chipBg, borderRadius: BorderRadius.circular(8)),
            child: Text(chip,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: chipFg)),
          ),
        ]),
      ),
    );
  }
}
