import 'package:flutter/material.dart';

import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

/// Bundle 216 (page 10): "Blocked on this phone" — the old 'Blocked
/// devices' sheet as a page. Only this phone, online or offline.
class AdminLocalBlockedScreen extends StatefulWidget {
  const AdminLocalBlockedScreen({
    super.key,
    required this.load,
    required this.unblock,
    this.onBlockUser,
  });

  /// `LocalStore.blockedUsersOverview()`.
  final Future<List<Map<String, Object?>>> Function() load;
  final Future<void> Function(String userId) unblock;

  /// "Block a user" on the empty card → page 8.
  final VoidCallback? onBlockUser;

  @override
  State<AdminLocalBlockedScreen> createState() => _AdminLocalBlockedScreenState();
}

class _AdminLocalBlockedScreenState extends State<AdminLocalBlockedScreen> {
  List<Map<String, Object?>>? _rows;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final rows = await widget.load();
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _rows = const []);
    }
  }

  static String nameOf(Map<String, Object?> r) {
    final d = r['display_name']?.toString().trim() ?? '';
    if (d.isNotEmpty) return d;
    final u = r['username']?.toString().trim() ?? '';
    if (u.isNotEmpty) return u;
    return r['user_id']?.toString() ?? '?';
  }

  static String subOf(Map<String, Object?> r) {
    final at = parseAdminTime216(r['blocked_at'] ?? r['created_at']);
    if (at != null) return 'Blocked ${dMMM216(at.toLocal())}';
    final u = r['username']?.toString().trim() ?? '';
    return u.isEmpty ? 'Blocked' : '@$u';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return AdminPage216(
      title: 'Blocked on this phone',
      subtitle: 'Only this phone, online or offline',
      children: [
        const SizedBox(height: 4),
        if (rows == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (rows.isEmpty)
          AdminEmptyState216(
            icon: Icons.verified_user_outlined,
            tone: A216Tone.green,
            title: 'Nobody is blocked here',
            body: 'To stop someone on every phone, use Blocked by admin.',
            button: widget.onBlockUser == null ? null : 'Block a user',
            onButton: widget.onBlockUser,
          )
        else
          AdminListCard216([
            for (final r in rows)
              AdminRow216(
                key: ValueKey('a216_local_blocked_${r['user_id']}'),
                height: 66,
                leading: AdminPersonAvatar216(
                  name: nameOf(r),
                  userId: r['user_id']?.toString(),
                  radius: 20,
                  blocked: true,
                ),
                title: nameOf(r),
                subtitle: subOf(r),
                trailing: AdminPillButton216(
                  'Unblock',
                  A216Tone.grey,
                  key: ValueKey('a216_local_unblock_${r['user_id']}'),
                  () async {
                    final id = r['user_id']?.toString() ?? '';
                    if (id.isEmpty) return;
                    await widget.unblock(id);
                    await _reload();
                    if (context.mounted) adminSnack216(context, '${nameOf(r)} unblocked on this phone.');
                  },
                ),
              ),
          ]),
      ],
    );
  }
}
