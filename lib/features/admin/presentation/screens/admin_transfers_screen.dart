import 'package:flutter/material.dart';

import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';

/// Bundle 216 (page 18): File transfers — only kind and size.
class AdminTransfersScreen extends StatelessWidget {
  const AdminTransfersScreen({super.key});

  static ({String title, IconData icon, A216Tone tone}) kindOf(Map<String, dynamic> f) {
    var k = '${f['kind'] ?? ''}';
    if (k.isEmpty) {
      final ct = '${f['content_type'] ?? ''}';
      k = ct.startsWith('image/')
          ? 'photo'
          : ct.startsWith('video/')
              ? 'video'
              : ct.startsWith('audio/')
                  ? 'voice'
                  : 'document';
    }
    return switch (k) {
      'photo' || 'image' => (title: 'Photo', icon: Icons.image_outlined, tone: A216Tone.blue),
      'video' => (title: 'Video', icon: Icons.videocam_outlined, tone: A216Tone.purple),
      'voice' || 'audio' => (title: 'Voice note', icon: Icons.mic_none_rounded, tone: A216Tone.teal),
      _ => (title: 'Document', icon: Icons.description_outlined, tone: A216Tone.red),
    };
  }

  static bool done(Map<String, dynamic> f) {
    final s = '${f['status'] ?? ''}';
    return s == 'complete' || s == 'completed' || s == 'done' || s == 'uploaded' || s == 'ready';
  }

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'File transfers',
      module: 'File Transfers',
      withDashboard: true,
      subtitle: (_) => 'Files sent and space used',
      builder: (context, state) {
        final c = A216.colors(context);
        final t = A216Text(c);
        final used = (state.summaryData?['file_storage_bytes'] as num?) ?? 0;
        double? disk;
        final comps = state.healthData?['components'];
        if (comps is List) {
          for (final x in comps) {
            if (x is Map && '${x['key']}' == 'storage' && x['value'] is num) {
              disk = (x['value'] as num).toDouble();
            }
          }
        }
        final now = adminNow216();
        final week = state.transfers.where((f) {
          final at = parseAdminTime216(f['created_at']);
          return at != null && now.difference(at).inDays < 7;
        }).length;
        final waiting = state.transfers.where((f) => !done(f)).length;
        return [
          AdminCard216(
            key: const ValueKey('a216_files_top'),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                    child: Text('${size216(used)} used',
                        style: t.custom(16, FontWeight.w700, c.ink))),
                if (disk != null) Text('Disk ${disk.round()}% full', style: t.cardSub),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  height: 10,
                  child: LinearProgressIndicator(
                    value: ((disk ?? 0) / 100).clamp(0.0, 1.0),
                    backgroundColor: A216.barTrack,
                    color: c.blue,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('${plural216(week, 'file')} this week · $waiting waiting', style: t.cardSub),
            ]),
          ),
          const SizedBox(height: 10),
          const AdminNote216('Only kind and size. Nobody can open the files.'),
          const SizedBox(height: 12),
          if (state.loading && state.transfers.isEmpty)
            const AdminLoading216()
          else if (state.transfers.isEmpty)
            const AdminEmptyState216(
                icon: Icons.swap_horiz_rounded,
                tone: A216Tone.teal,
                title: 'No files yet',
                body: 'Files people send show here with kind and size.')
          else
            AdminListCard216([
              for (final f in state.transfers)
                () {
                  final k = kindOf(f);
                  final who = '${f['owner_name'] ?? ''}'.trim().isEmpty ? 'Someone' : '${f['owner_name']}';
                  return AdminRow216(
                    key: ValueKey('a216_file_${f['id']}'),
                    height: 62,
                    leading: AdminToneIcon216(k.icon, k.tone),
                    title: k.title,
                    subtitle:
                        '$who · ${size216((f['size'] as num?) ?? 0)} · ${whenSub216(f['created_at'])}',
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: done(f)
                          ? const AdminTag216('Done', A216Tone.green)
                          : const AdminTag216('Waiting', A216Tone.orange),
                    ),
                  );
                }(),
            ]),
        ];
      },
    );
  }
}
