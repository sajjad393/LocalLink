# APPLY app 313 - "1 missed", My links, Get chats back from friends, Conversations page (3.0.106+177)

Base: app 312 (3.0.105+176) = `9ec8f68` (pushed, CI OK). App only (no backend zip).
Scope: TODO 313 A, B, C, D, E (all). Details + "As built" in `docs/history/TODO_313.md`.

## What changes for the user
- **A (Calls):** "1 missed" never breaks into "1" / "missed" on two lines (no-break spaces).
- **B (My links):** a person straight above You no longer counts as "left" by a rounding speck, so
  kiran and ayesha are spread one each side of You and the lines don't run under the names.
- **C (My links, small map):** the "Server" name has a small card-coloured pill; the line and its moving
  dot pass behind it (big admin map unchanged).
- **D (NEW) Get chats back from friends:** after a fresh install (phone has no messages) the app asks
  each friend who comes near, for 30 days, for the 1-to-1 and group messages (words + voice notes) that
  this phone is missing. The friend's phone sends by itself, no pop-up, friends only, only over the locked
  link, only your chat with that friend (and groups you are both in). Also Settings -> Chats ->
  "Get chats back from friends" (any time). Messages come back read, no notification. A toast on Home
  says "Got 450 messages back from kiran". English + Urdu.
  The friend must have 3.0.106 too (an older app ignores the ask).
- **E (Conversations page):** full title (the Server pill moves under it on a small phone); no grey square
  corners behind the Live card; "+ New request" has room at both ends; "1 part" (not "1 parts"); no text
  ends in "..." on any phone size - long names / lines wrap; tabs and blue buttons shrink the words a
  little instead of cutting them.

## Files (38)
- A: `lib/features/calls/presentation/widgets/call_history_tile.dart`
- B: `lib/features/admin/presentation/widgets/link_balance_298.dart`
- C: `lib/features/admin/presentation/widgets/link_paths_map.dart` (sha-locked, approved; new sha in
  `test/link_paths_zoom_222_test.dart`)
- D: NEW `lib/features/messaging/data/services/chat_restore_313.dart`,
  NEW `lib/features/messaging/data/services/chat_restore_store_313.dart`,
  NEW `lib/features/messaging/presentation/widgets/restore_chats_row_313.dart`,
  `lib/core/services/local_store.dart`, `lib/features/connectivity/data/services/sealing_peer_transport.dart`,
  `lib/features/messaging/data/services/reliable_messaging_service.dart`,
  `lib/features/groups/data/services/group_nearby_service.dart`, `lib/app/app_dependencies.dart`,
  `lib/app/local_link_app.dart`, `lib/features/home/presentation/screens/home_screen.dart`,
  `lib/features/home/presentation/screens/messenger_settings_screen.dart`
- E: `lib/features/admin/presentation/screens/admin_conversations_screen.dart`,
  `lib/features/admin/presentation/widgets/conversations_kit307.dart`,
  `lib/features/admin/data/actions/request_step_307.dart`
- Words: `lib/l10n/app_en.arb`, `lib/l10n/app_ur.arb` (12 keys) + `lib/l10n/gen/*` (3)
- Version: `pubspec.yaml`, `lib/core/config/app_build.dart`; `test/bundle223_logs_test.dart`,
  `test/nearby_190_test.dart` (version only)
- Old test changed (listed in TODO A): `test/calls_group_171_test.dart` (no-break spaces)
- NEW tests (8): `calls_missed_313`, `link_balance_313`, `chat_restore_313`, `chat_restore_store_313`,
  `group_restore_313`, `seal_locked_only_313`, `restore_row_313`, `conversations_313`
- `docs/history/TODO_313.md`, `docs/history/APPLY_app_313.md`

## Tests
| Check | Command | Result |
|---|---|---|
| New tests | `flutter test --no-pub test/*_313_test.dart` | 73 pass, EXIT 0 |
| Fix proof A | `calls_missed_313` on 312 code | fails (Expected 1 line, Actual 2) |
| Fix proof B | `link_balance_313` on 312 code | fails |
| Fix proof E | `conversations_313` matrix on 312 code | 24 of 24 fail (cut text / overflow) |
| Full app suite | 327 files in 14 chunks | 3202 pass (3129 old + 73 new), 0 fail, all EXIT 0, `[E]`=0 |
| Analyze | `flutter analyze --no-pub` | 361 issues, all old; 0 in the 313 files |

E matrix: 320 / 360 / 411 dp x text size 1.0 / 1.3 x light / dark x English / Urdu (24 cases):
no overflow, no text past its lines, no "..." set, title "Conversations" whole.
The new E test found 2 more real overflows (request row chip + range + Cancel at 320 dp; a long Urdu
chip) - fixed. The new Settings-row test found a real bug (an unsortable group list stopped the ask) - fixed.

## Known limitations
- D: restore packets are best-effort (not queued): if the friend walks away mid-way, missing messages
  are asked again once, then the friend is asked again 10 min later.
- D: messages deleted "for me" before the reinstall can come back; restored 1-to-1 / older group messages
  are trusted from the friend's locked link (no signature); a friend who also reinstalled has nothing
  to give; photos / videos / files are not restored (only words + voice notes).
- D: the Settings-row mock was not shown before Build.

## Not checked
- Real phones: D between 2 real phones, A/B/C/E on the C71. NOT VERIFIED.
- Real Android build: CI builds it.

## Phone checks
1. Calls: ayesha's row reads "No answer, 9:30 PM ·" / "1 missed" (never "1" / "missed").
2. My links with sumaira offline + kiran and ayesha on Local Wi-Fi: one on each side of You; the server
   line passes behind the "Server" pill.
3. Conversations page on the C71 (light + dark, English + Urdu): full title, no grey corners behind the
   Live card, "+ New request" text not touching the end, Finished says "1 part", no "..." anywhere.
4. Get chats back: update kiran AND ayesha to 3.0.106 first. Then on ayesha: uninstall, install 3.0.106,
   log in, open LinkUp near kiran (same Wi-Fi). Within about a minute the chat with kiran comes back
   (Home toast "Got N messages back from kiran"); voice notes play. Settings -> Chats -> "Get chats back
   from friends" shows "Done". Shared groups get older messages too.
5. Regression: normal chat, voice notes, calls (speaker off by default), group messages, Get chat,
   Settings (all other rows), Urdu.
