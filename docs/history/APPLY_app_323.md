# APPLY app 323 — offline picker, group phones, delete, file queue, honest words (3.0.115+186)

Build **186** = the 185 build plus P5 + P6 (the two items you said yes to). If you already built the 185 zip (3.0.114+185), build this one instead — it is 3.0.115+186 and supersedes it.

Base: app **322** = `8a06dd1` (3.0.113+184). **Backend is NOT part of 323** — nothing here needs a server change, `b3f3c32` stays as it is. Push app only, no server restart needed.
Plan: `docs/history/PLAN_323.md`, details: `docs/history/TODO_323.md`.

## What changes for the user
- **New request → Group → Pick (P1):** with the server off, the picker shows **every group the Conversations list shows** — it is seeded from the saved conversations as well, not only from the list the picker itself saved. A group the saved server list already knew keeps its saved phones (`member_devices`).
- **Offline Get chat for a group (P2):** the group list and its phones are now saved on every successful **Conversations** load (`/admin/groups` + the server's nearby groups), not only when the picker happens to be opened. Server on for a minute → offline Get chat works for every group on screen.
- **"Delete locally" on a group (P4):** works again. The delete statement had been cut off (`local_path != ` with nothing after it) since bundle 308, so SQLite answered "incomplete input" and the whole transaction rolled back — nothing was ever deleted (17 Nov 18:41:32 / 18:41:39 / 18:42:01).
- **Photos / videos / voice notes that were planned but never asked (P7):** the queue no longer counts its own in-flight asks as "pending cards", so the 3-card window no longer reads as full from its own two asks and asks nothing (17 Nov 18:45:58: `files=6`, not one `FILE_QUEUE_ASKED` in the hour).
- **New log lines (P3, P7 — no UI):** `PICKER_LIST323 src=server|saved+chats|saved|chats|local known= shown= mine=`, `GET_CHAT_FAIL323 why=targets_empty|same_phone|own|own_devices|already|actions_not_ready`, `GROUPS_SAVED323 groups=N`, `ADMIN_GROUPS_LIST323_SKIP`, `FILE_QUEUE_SKIP323 why=window on_way= cards= left=` (once per change).
- **Honest offline words (P5):** with the server off and a chat's phones not known, the app says **"Server off - this group's phones are not known yet."** (or "…this person's phone…") instead of the dead-end "This phone doesn't know their phones yet.". Online the old sentence stays — there it is true. New words in English **and** Urdu (`serverOffGroupPhones324`, `serverOffPersonPhone324`, wrapped RLI/PDI like every other Urdu line).
- **The saved list says when it was saved (P6):** every successful Conversations load stamps the list; offline the Conversations header shows one small grey line under the title — **"Saved 18:44"**, or **"Saved 16 Nov 18:44"** for another day, and nothing when this phone never saved one. While the server answers, no line: the list is today's. This is the only new UI in 323, and it is the line you approved.
- **Not changed:** sealing, calls, video, grey bubbles, the 321 status line, 320 Conversations rows / buttons, 318 kept copy, the 322 retry ladder (1→2→5→10 min, max 5), the group outbox, the app never touches Wi-Fi.

## Files (16 + docs)
- `lib/core/config/app_build.dart` — `3.0.115+186`
- `lib/core/services/local_store.dart` — P4
- `lib/features/admin/data/actions/chat_answer_reader.dart` — P1, P2, P3, P5, P6 (stamp)
- `lib/features/admin/data/actions/file_queue_317.dart` — P7
- `lib/features/admin/presentation/screens/admin_conversations_screen.dart` — P6 (the one grey line)
- `lib/l10n/app_en.arb`, `lib/l10n/app_ur.arb` — 2 new words
- `lib/l10n/gen/app_localizations.dart`, `..._en.dart`, `..._ur.dart` — the same 2 words
- `lib/l10n/by_english_304.dart` — English → Urdu for the 2 words
- `pubspec.yaml` — `version: 3.0.115+186`
- `test/bundle323_test.dart` — **new**, 18 tests
- `test/bundle223_logs_test.dart` — version asserts
- `test/nearby_190_test.dart` — version assert
- `test/bundle321_redesign_test.dart` — fixture clock (see below)
- `docs/history/PLAN_323.md`, `docs/history/TODO_323.md`, `docs/history/APPLY_app_323.md` (`git add -f`)

## Old tests changed (listed)
- **Version:** `bundle223_logs_test` (3.0.115 / 186 / stamp), `nearby_190_test` (pubspec string).
- **`bundle321_redesign_test` — a clock, not code.** Its file rows were built at a fixed `2026-11-17T12:01:00Z`. Rows older than the plan count as old manual cards (321 F7) and are skipped, so from 12:01 UTC on 17 Nov the test started failing. **Reproduced on HEAD `8a06dd1` with the 323 code swapped out** — it is not caused by 323. The fixture is now `now + 1 min`, which is what the F7 rule asks for; no product code touched.
- No other test file changed.

## Tests (Linux sandbox, Flutter 3.47.7 / Dart 3.13.5 — the CI pin)
| Check | Result |
|---|---|
| New `test/bundle323_test.dart` | **18 / 18 pass** |
| Full app suite, 346 files (345 suites + `admin_test_support.dart` helper, no `main`), chunks of ~22 | **3443 pass, 0 fail.** The only non-zero chunk exit is the helper file: `flutter test` cannot "load" a support file that has no `main` — it is not run, and it is not a test. |
| Urdu / words | `urdu_304_test` + the words locks in 307/320/321: **75 pass** — the 2 new keys have Urdu words, RLI/PDI wrapping, and the same placeholders |
| `flutter analyze` | **0 errors**; the new words and the one UI line add no warnings (the file's `CustomClipper` warnings are pre-existing) |

What the new tests lock (one per claim):
1. picker offline shows the saved-chat groups (`g-g1`, `g-g2`) with their member counts;
2. a group in the saved **server** list keeps `member_devices ['d1','d2']` — it is not replaced by the chats row;
3. `conversations()` really writes `/admin/groups` into the saved list;
4. offline `resolve314(group)` returns `targets ['d1','d2']` — the exact 17 Nov dead end;
5. a failed group fetch keeps the old list (never wipes a good list);
6. `PICKER_LIST323` says `src=server` / `saved` / `local`;
7. `GET_CHAT_FAIL323 why=actions_not_ready` is logged;
8. queue-made cards do not fill the 3-card window (`asked == ['c','d']`);
9. 3 foreign pending cards still block, and `FILE_QUEUE_SKIP323` is logged **once** over 3 ticks;
10. `deleteGroupLocal`'s SQL ends with `!= ''` (bundle 308 lock);
11. offline words: group / person / online (old sentence kept), and the throw uses the helper + the live server state;
12. `conversations()` stamps the list and `savedAt323()` reads it back;
13. the label: "Saved 18:44" today, a date on another day, nothing when never saved;
14. offline, the Conversations header really shows that line (widget test) with the saved list on screen.

## Status: READY WITH KNOWN LIMITATIONS
- **NOT VERIFIED on phones.** No device here. The APK is yours.
- P5/P6 are in this build (both approved 17 Nov).
- P2 needs one **successful Conversations load while the server answers** before the offline picker/Get chat can know a group's phones. On the 17 Nov log the owner phone was offline from 18:47:58, so the list it had was the last good one.
- Not touched, still open from 322: W6 (N1–N6), S8 `label_current`, W1–W3, the 322 APK checks.

## Phone checks (then one log)
1. Server **ON** → open Conversations (this is what saves the group list) → open **Group 1** and come back.
2. Server **OFF** → New request → Group → Pick: Group 1, Group 2, Group 3 all there (`PICKER_LIST323 src=saved+chats` or `saved`).
3. Server still OFF → Get chat on a group → the request goes out (card + buzz on the other phone); if that group's phones were never learned you now get `GET_CHAT_FAIL323 why=targets_empty` instead of silence.
4. A chat with 6 photos: the files card fills; `FILE_QUEUE_ASKED` appears (and, if it waits, `FILE_QUEUE_SKIP323 why=…` once).
5. Conversations → long-press a group → **Delete locally** → gone, and no SQL error in the log.
6. **P6:** server off → the Conversations title line shows **"Saved 18:44"**; server on + Conversations opened again → the line is gone.
7. **P5:** server off → Get chat on a group whose phones were never learned → **"Server off - this group's phones are not known yet."** (Urdu: سرور بند - اس گروپ کے فون ابھی معلوم نہیں).
8. Regression: normal Get chat on a direct chat, Ready/grey status line, kept copy (318), 320 rows, Urdu + dark + big text.
9. Share the log — the lines to look for are `PICKER_LIST323`, `GROUPS_SAVED323`, `GET_CHAT_FAIL323`, `FILE_QUEUE_SKIP323`.

## Apply
```
git checkout -b b323 origin/main        # origin/main = 8a06dd1
git apply --check app_323.patch
git apply app_323.patch
flutter pub get
flutter test test/bundle323_test.dart    # 18 tests
flutter build apk
```
The patch also adds `docs/history/PLAN_323.md`, `TODO_323.md`, `APPLY_app_323.md` (they are git-ignored in the repo, so in the repo itself they are added with `git add -f`).
