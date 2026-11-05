import 'package:flutter/material.dart';

import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';

/// Bundle 216 (page 22): Privacy & access — what admins can never see.
class AdminPrivacyScreen extends StatelessWidget {
  const AdminPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'Privacy & access',
      module: 'Privacy & Access',
      subtitle: (_) => 'What admins can never see',
      builder: (context, state) {
        final c = A216.colors(context);
        final t = A216Text(c);
        final p = state.privacyData;
        if (p == null) return [if (state.loading) const AdminLoading216()];
        bool hidden(String k) => p[k] != true;
        final never = <(String, String, IconData)>[
          if (hidden('passwords_exposed')) ('passwords', 'Passwords', Icons.password_rounded),
          if (hidden('private_keys_exposed')) ('keys', 'Private keys', Icons.key_rounded),
          if (hidden('private_call_audio_exposed') && hidden('decrypted_call_media_exposed'))
            ('audio', 'Call audio', Icons.call_outlined),
          if (hidden('private_file_contents_exposed'))
            ('files', 'File contents', Icons.description_outlined),
          if (hidden('private_message_bodies_exposed'))
            ('messages', 'Message text', Icons.chat_bubble_outline_rounded),
        ];
        final ownerOnly = p['private_message_bodies_exposed'] == true;
        AdminRow216 row(String key, String title, String? sub, IconData icon, A216Tone tone,
                String tag) =>
            AdminRow216(
              key: ValueKey('a216_privacy_$key'),
              height: sub == null ? 54 : 60,
              leading: AdminToneIcon216(icon, tone),
              title: title,
              subtitle: sub,
              trailing: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: AdminTag216(tag, tone),
              ),
            );
        return [
          AdminCard216(
            key: const ValueKey('a216_privacy_head'),
            fill: const Color(0xFFECFDF3),
            border: const Color(0xFFABEFC6),
            shadow: false,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              const AdminToneIcon216(Icons.verified_user_outlined, A216Tone.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Private things stay private', style: t.custom(14.5, FontWeight.w600, c.ink)),
                  const SizedBox(height: 3),
                  Text('Checked by the server for every admin', style: t.cardSub),
                ]),
              ),
            ]),
          ),
          const AdminSection216('Never shown to admins'),
          AdminListCard216([
            for (final n in never) row(n.$1, n.$2, null, n.$3, A216Tone.green, 'Never shown'),
          ]),
          if (ownerOnly) ...[
            const AdminSection216('Owner only'),
            AdminListCard216([
              row(
                  'message_text',
                  'Message text',
                  p['message_body_access_audited'] == true
                      ? 'Owner can read; every open is saved'
                      : 'Owner can read',
                  Icons.chat_bubble_outline_rounded,
                  A216Tone.orange,
                  'Owner'),
            ]),
          ],
          const AdminSection216('Always'),
          AdminListCard216([
            if (p['administrative_actions_audited'] != false)
              row('audited', 'Admin actions saved', null, Icons.list_alt_rounded, A216Tone.blue,
                  'Always'),
            if (p['server_side_role_checks'] != false)
              row('roles', 'Rights checked by the server', null, Icons.shield_outlined,
                  A216Tone.blue, 'Always'),
          ]),
        ];
      },
    );
  }
}
