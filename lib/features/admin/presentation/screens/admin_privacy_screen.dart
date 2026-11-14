import 'package:flutter/material.dart';

import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 216 (page 22): Privacy & access — what admins can never see.
class AdminPrivacyScreen extends StatelessWidget {
  const AdminPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: L.t.privacyAccess,
      module: 'Privacy & Access',
      subtitle: (_) => L.t.whatAdminsCanNeverSee,
      builder: (context, state) {
        final c = A216.colors(context);
        final t = A216Text(c);
        final p = state.privacyData;
        if (p == null) return [if (state.loading) const AdminLoading216()];
        bool hidden(String k) => p[k] != true;
        final never = <(String, String, IconData)>[
          if (hidden('passwords_exposed')) ('passwords', L.t.passwords, Icons.password_rounded),
          if (hidden('private_keys_exposed')) ('keys', L.t.privateKeys, Icons.key_rounded),
          if (hidden('private_call_audio_exposed') && hidden('decrypted_call_media_exposed'))
            ('audio', L.t.callAudio, Icons.call_outlined),
          if (hidden('private_file_contents_exposed'))
            ('files', L.t.fileContents, Icons.description_outlined),
          if (hidden('private_message_bodies_exposed'))
            ('messages', L.t.messageText, Icons.chat_bubble_outline_rounded),
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
                  Text(L.t.privateThingsStayPrivate, style: t.custom(14.5, FontWeight.w600, c.ink)),
                  const SizedBox(height: 3),
                  Text(L.t.checkedByTheServerForEvery, style: t.cardSub),
                ]),
              ),
            ]),
          ),
          AdminSection216(L.t.neverShownToAdmins),
          AdminListCard216([
            for (final n in never) row(n.$1, n.$2, null, n.$3, A216Tone.green, L.t.neverShown),
          ]),
          if (ownerOnly) ...[
            AdminSection216(L.t.ownerOnly),
            AdminListCard216([
              row(
                  'message_text',
                  L.t.messageText,
                  p['message_body_access_audited'] == true
                      ? L.t.ownerCanReadEveryOpenIs
                      : L.t.ownerCanRead,
                  Icons.chat_bubble_outline_rounded,
                  A216Tone.orange,
                  'Owner'),
            ]),
          ],
          AdminSection216(L.t.always),
          AdminListCard216([
            if (p['administrative_actions_audited'] != false)
              row('audited', L.t.adminActionsSaved, null, Icons.list_alt_rounded, A216Tone.blue,
                  L.t.always),
            if (p['server_side_role_checks'] != false)
              row('roles', L.t.rightsCheckedByTheServer, null, Icons.shield_outlined,
                  A216Tone.blue, L.t.always),
          ]),
        ];
      },
    );
  }
}
