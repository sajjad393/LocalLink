# APPLY app 314 - my own chats left out, one open request per chat, nearby groups, notification like the card (3.0.107+178)

Base: app 313 (3.0.106+177) = `e6bfc11` (pushed, CI 43753818604 success). Backend 314 goes FIRST
(`APPLY_backend_314.md`); this app also works with the old server (it keeps the group notes until the
server has 314).
Scope: TODO 314 Issue 1, 1b, 1c, 3 + K1-K11 (all). Details + "As built" in `docs/history/TODO_314.md`.

## What changes for the user
- **Issue 1 - my own chats:** New request has no "Me" row and no "You already have this chat" note. The
  group list shows every group I am NOT in: the server's groups, groups this phone knows, and nearby groups
  members reported ("Study group · Nearby · 4 members"). On Chats, my own chats say "On your phone": no
  Get chat button, the row does nothing. Asking my own chat anyway (online or offline) says "You are in
  this chat. It's already on your phone."
- **Issue 1b - one open request per chat:** when the chat already has a Sent / Reached / Coming request
  (any range), the sheet shows "Already asked · Open it" and Get chat is off; the box opens that request's
  card. A Chats row with an open request opens its card (never a second sheet). Ready / cancelled /
  No messages / closed don't block.
- **K5 - offline Chats tab:** with no server it lists the last server list saved on this phone (no message
  text; my own chats left out) + the nearby groups reported to this phone. Get chat from it goes the
  offline way.
- **Issue 1c - nearby group notes:** every phone sends a small signed note for each phone-only group it is
  in (name, member phones, made time - no messages, no keys) to the server and, locked, to the Owner's
  phone when linked. Again on a name / member change, else once a day. Also in the background while the
  LinkUp keep-alive runs (no new permission, no notification). The Owner phone keeps notes only from
  members, signed or from the writer itself.
- **Issue 3 - the notification (pick B):** Android 16+: chat bubble at the start, check at the end, a ring
  that moves along in the step colour (orange Sent / Reached, blue Coming, green Ready) and rocks a little
  every 3 s while waiting (stops after 10 min, when parts come, Ready, or Cancel). Android 15 and older:
  the sliding line while waiting, a filled bar once parts come.
- **K11 - "2h" on a new request:** the time is corrected by the server PC clock difference (the Settings
  bar "Server PC clock is 3 h slow" still tells you to fix the PC clock).

## Files (24)
- Issue 1 / 1b / K5: `lib/features/admin/data/actions/chat_answer_reader.dart`,
  `lib/features/admin/presentation/screens/admin_chat_request_sheet.dart`,
  `lib/features/admin/presentation/screens/admin_conversations_screen.dart`
- Issue 1c: NEW `lib/features/admin/data/actions/group_notes_314.dart`, `lib/app/app_dependencies.dart`
- Issue 3 / K11: `lib/features/admin/data/actions/chat_request_notifier_307.dart`,
  `android/app/src/main/kotlin/com/sajjad/locallink/ChatRequestNotifier307.kt`,
  NEW `android/app/src/main/res/drawable/ic_req314_start.xml`, `ic_req314_end.xml`, `ic_req314_tracker.xml`
- Words: `lib/l10n/app_en.arb`, `lib/l10n/app_ur.arb` (8 keys) + `lib/l10n/gen/*` (3)
- Version: `pubspec.yaml`, `lib/core/config/app_build.dart`; `test/bundle223_logs_test.dart`,
  `test/nearby_190_test.dart` (version only)
- Old test changed (Issue 1, Me row removed): `test/bundle254_test.dart` (picker test: Me row absent; the
  "Me + noshad" send part removed - that chat is refused now)
- NEW tests: `test/conversations_314_test.dart` (22), `android/app/src/test/kotlin/com/sajjad/locallink/ChatRequest314Test.kt` (6)
- `docs/history/TODO_314.md`, `docs/history/APPLY_app_314.md`

## Tests
| Check | Command | Result |
|---|---|---|
| New Dart tests | `flutter test --no-pub test/conversations_314_test.dart` | 22 pass, EXIT 0 |
| New Kotlin tests | kotlinc + JUnit (sandbox kit) | `ChatRequest314Test` 6 pass; all Kotlin 511 OK (505 old) |
| Old tests near the change | 10 files (221a/b, 254, 255, 307, 310, 313, 312 start, crown 290, notifier 307) | 147 pass + 1 expected fail before the listed change (bundle254 "Me on top"), then pass |
| Full app suite | 328 files in 14 chunks | 3224 pass (3202 old + 22 new), 0 fail, all EXIT 0, `[E]`=0 |
| Analyze | `flutter analyze` | 361 issues, all old; 0 in the 314 files |
| Look | sheet + Chats rows rendered light + dark (test render) | "Already asked · Open it" box, Get chat off, "On your phone" row - OK |

Fix proof: the new tests use names that don't exist in 313 code (they can't pass there); the
bundle254 picker test showed the old "Me" row before the change.

## Known limitations
- 1c: a member phone sends the locked note only to an Owner phone it has the key of (a friend, or the
  crown card + directory) and only while linked; otherwise the server carries it. Notes are not sent when
  Android killed / force-stopped LinkUp or keep-alive is off.
- 1c: a group the Owner's phone learns only from a note is asked the offline way only while the member
  phones come near (same as every offline Get chat).
- 1b: the phone matches "same people" by account or phone ids it knows; a request it cannot match is
  still refused by the server (the sheet then shows that request).
- 3: Android allows no real animation in notifications - the ring moves by re-posting every 3 s
  (silent, same card). Android may slow re-posts down.

## Not checked
- Real phones (C71 Android 16 look, ZTE plain bar, notes between real phones in the background). NOT VERIFIED.
- Real Android build: CI builds it.

## Phone checks
1. New request (C71, server on): no "Me"; groups list has no group you are in; a nearby group shows
   "Nearby · N members".
2. Chats tab: your own chats say "On your phone", no Get chat; tapping them does nothing.
3. Ask kiran & ayesha twice: the second time "Already asked · Open it" opens the first card.
4. Notification on the C71: bubble -> orange ring rocking -> check; the time says "now", not "2h".
5. Server off: Chats tab shows the saved list (no own chats) + reported groups; Get chat there sends cards.
