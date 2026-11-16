# APPLY app 320 - Conversations + chat viewer redesign (3.0.111+182)

Base: app 319 (3.0.110+181) = `d6c0cab` (pushed). **App only** - backend stays `8110af0`.
Plan + as built: `docs/history/TODO_320.md`.

## What changes for the user (Owner phone)
- Conversations: one list, no tabs. Search "Find a chat", chips All / Coming / Ready / Kept with counts.
- "Now" card: only requests on their way, one line each (blue coming, orange waiting + age, bar "40 of 80 parts"), X cancels (asks first).
- "Chats" card: every chat once, one button: Open / New (kept copy -> new messages only) / Get chat. Cancelled = "Cancelled · 14 Nov".
- No sliding Live card, no auto-advance, no "In progress" copy.
- Chat viewer: grey bubble shapes while loading; waiting card (who, Asked, Sent to N phones, Cancel request); coming strip + "More messages on the way..."; kept copy = one green "Kept on this phone until ..." line.
- Not changed: grey bubbles, New request sheet, live notification, sealing, calls, 319 fixes. Web owner page unchanged (R9 not done).

## Files
- `lib/features/admin/presentation/screens/admin_conversations_screen.dart`, `admin_chat_viewer_screen.dart`
- NEW `lib/features/admin/presentation/widgets/conversations_kit320.dart`
- `lib/l10n/app_en.arb`, `app_ur.arb`, `lib/l10n/gen/*` (31 new words)
- Version: `pubspec.yaml`, `lib/core/config/app_build.dart`, `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart`
- Old tests changed (locked the old design): `bundle221b`, `conversations_307`, `conversations_313`, `conversations_314`, `bundle318`
- NEW test `test/bundle320_test.dart` (23)
- `docs/history/TODO_320.md`, `docs/history/APPLY_app_320.md`

## Tests (Linux sandbox)
| Check | Result |
|---|---|
| New Dart tests | bundle320 23 pass |
| Full app suite, 333 files | 3320 pass + 2 fail: `bundle210a_server_test` (known flaky) + `call_295_test` G1-2 (ran with analyze at the same time; alone 4/4 pass, no call code changed). 3322 = 3299 + 23 new |
| Version tests after bump | bundle223_logs + nearby_190 +19 |
| Kotlin | 520 OK (unchanged) |
| Analyze | 361 issues = base `d6c0cab` (361), 0 new |
| Screens | widget screenshots list + 4 viewer states, light + dark (sandbox) |

## Known limitations
- NOT VERIFIED on phones.
- "Last seen" is not shown on the waiting card (the Owner phone does not know it).
- Web owner page keeps the old look (R9 only if you agree).

## Phone checks
1. Owner: Conversations - each chat once; chips count right; nothing slides by itself.
2. Get chat kiran: the row shows in "Now" (orange waiting, then blue "40 of 80 parts"); X asks then cancels.
3. Open it while waiting: waiting card + Cancel request; while coming: strip + shimmer rows.
4. Kept copy: "New" gets only new messages; viewer shows "Kept on this phone until ...".
5. Urdu + dark mode + big text: no cut words.
6. Regression: New request sheet, live notification, kept copy (318), files (317), calls.
