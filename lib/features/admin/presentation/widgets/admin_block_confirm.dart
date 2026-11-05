import 'package:flutter/material.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';

/// Bundle 212: who is being blocked / unblocked.
class BlockTarget {
  final String userId;
  final List<String> deviceIds;
  final String name;
  final String username;
  final String seen; // "nearby now" / "seen 2 days ago" / ''

  const BlockTarget({
    required this.userId,
    this.deviceIds = const <String>[],
    required this.name,
    this.username = '',
    this.seen = '',
  });

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'[\s\-_]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    return parts.map((w) => w[0]).take(2).join().toUpperCase();
  }
}

const Color kBlockRed = Color(0xFFB42318);
const Color kBlockRedTint = Color(0xFFFDEBE9);
const Color kUnblockGreen = Color(0xFF15803D);
const Color kUnblockGreenTint = Color(0xFFE3F6EA);

/// Bundle 212 (E3, mock page 3): the new "asks first" pop-up. True = go.
Future<bool> showAdminBlockConfirm(BuildContext context,
    {required BlockTarget target, required bool block}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AdminBlockConfirmDialog(target: target, block: block),
  );
  return ok == true;
}

class AdminBlockConfirmDialog extends StatelessWidget {
  const AdminBlockConfirmDialog(
      {super.key, required this.target, required this.block});

  final BlockTarget target;
  final bool block;

  @override
  Widget build(BuildContext context) {
    final main = block ? kBlockRed : kUnblockGreen;
    final tint = block ? kBlockRedTint : kUnblockGreenTint;
    final first = target.name.split(' ').first;
    final rows = block
        ? <(IconData, Color, String, String)>[
            (Icons.block, kBlockRed, 'No messages or calls',
                "Can't send or get them on any phone"),
            (Icons.wifi_tethering, const Color(0xFF1E5BFF), 'Goes out right away',
                'Nearby phones now, server when online'),
            (Icons.check, kUnblockGreen, 'Old chats stay',
                '$first can still read them. Unblock anytime'),
            (Icons.hub_outlined, const Color(0xFF1E5BFF), 'Still helps the mesh',
                "The phone carries others' locked messages"),
          ]
        : <(IconData, Color, String, String)>[
            (Icons.chat_bubble_outline, kUnblockGreen, 'Messages and calls work again',
                'On every phone the unblock reaches'),
            (Icons.wifi_tethering, const Color(0xFF1E5BFF), 'Goes out right away',
                'Nearby phones now, server when online'),
            (Icons.login, kUnblockGreen, 'No new sign-in',
                '$first can use LinkUp at once'),
          ];
    return Dialog(
      key: const ValueKey('admin_block_confirm'),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), // 216
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: tint,
            child: Icon(block ? Icons.block : Icons.lock_open_rounded,
                color: main, size: 30),
          ),
          const SizedBox(height: 12),
          Text(block ? 'Block ${target.name}?' : 'Unblock ${target.name}?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827))),
          const SizedBox(height: 4),
          const Text('For everyone, on all LinkUp phones',
              style: TextStyle(fontSize: 13.5, color: Color(0xFF5B6472))),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F6F8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E6EC)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFEDE7FB),
                child: Text(target.initials,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6D4BC4))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(target.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      if (target.username.isNotEmpty || target.seen.isNotEmpty)
                        Text(
                            [
                              if (target.username.isNotEmpty) '@${target.username}',
                              if (target.seen.isNotEmpty) target.seen,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, color: Color(0xFF5B6472))),
                    ]),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                CircleAvatar(
                    radius: 14,
                    backgroundColor: r.$2.withValues(alpha: 0.12),
                    child: Icon(r.$1, size: 15, color: r.$2)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.$3,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                        Text(r.$4,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF5B6472))),
                      ]),
                ),
              ]),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              key: const ValueKey('admin_block_confirm_go'),
              style: FilledButton.styleFrom(
                  backgroundColor: main,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder()),
              onPressed: () => Navigator.pop(context, true),
              child: Text(block ? 'Block for everyone' : 'Unblock for everyone',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFF5B6472))),
          ),
        ]),
      ),
    );
  }
}

/// Asks first, then blocks / unblocks for everyone. True when done.
Future<bool> runAdminBlock(BuildContext context,
    {required AdminBlockService? service,
    required BlockTarget target,
    required bool block}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (service == null) {
    messenger?.showSnackBar(const SnackBar(
        content: Text('Offline blocking is not ready yet.')));
    return false;
  }
  if (!await showAdminBlockConfirm(context, target: target, block: block)) {
    return false;
  }
  try {
    await service.setBlocked(
      targetUserId: target.userId,
      targetDevices: target.deviceIds,
      targetName: target.name,
      block: block,
    );
    messenger?.showSnackBar(SnackBar(
        content: Text(block
            ? '${target.name} is blocked for everyone.'
            : '${target.name} is unblocked for everyone.')));
    return true;
  } on StateError catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Could not save: $e')));
  }
  return false;
}
