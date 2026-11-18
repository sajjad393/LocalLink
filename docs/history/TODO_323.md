# TODO 323 — what is done, what is not (3.0.115+186)

Built on app 322 (`8a06dd1`). Backend untouched. Spec = `LOG_REVIEW_17Nov_1857.md` §4.

## Done in this build (code)

| # | Fix | File | What you will see |
|---|---|---|---|
| **P1** | Group picker seeded from the saved conversations | `chat_answer_reader.dart` → `pickerGroups314` | Server off, picker open → **all** the groups the Conversations list shows (Group 1/2/3), not one. A group the saved server list already knew keeps its phones. |
| **P2** | Group list + `member_devices` refreshed on every Conversations load | `chat_answer_reader.dart` → `_saveGroups323` (called from `_chats321`) | Server on for one minute, Conversations opened → offline Get chat works for every group on screen. |
| **P3** | The silent exits log why | `chat_answer_reader.dart` | `PICKER_LIST323 src=… known=… shown=… mine=…`, `GET_CHAT_FAIL323 why=targets_empty\|same_phone\|own\|own_devices\|already\|actions_not_ready`, `GROUPS_SAVED323 groups=N`, `ADMIN_GROUPS_LIST323_SKIP`. |
| **P4** | `deleteGroupLocal` SQL fixed | `local_store.dart` | "Delete locally" on a group actually deletes (broken since 3.0.102+173 / bundle 308). |
| **P7** | File queue no longer fills its own window | `file_queue_317.dart` | Photos/videos/voice notes that are planned actually get asked; when the queue still waits you get `FILE_QUEUE_SKIP323 why=window on_way=… cards=… left=…` once per change instead of silence. |
| **P5** | Honest words when the server is off and the phones are not known | `chat_answer_reader.dart`, `lib/l10n/*` | Instead of the dead end "This phone doesn't know their phones yet.": **"Server off - this group's phones are not known yet."** / **"…this person's phone…"** (English + Urdu). Online the old sentence stays - there it is true. |
| **P6** | The saved Conversation list says when it was saved | `chat_answer_reader.dart` (stamp), `admin_conversations_screen.dart` (one grey line) | Offline, under the Conversations title: **"Saved 18:44"** (or "Saved 16 Nov 18:44" for another day). Nothing while the server answers. |
| — | Version | `pubspec.yaml`, `app_build.dart` | `3.0.115+186` ("v3 · 3.0.115+186" on the App-version page). |
| — | Test lock | `test/bundle323_test.dart` (new) | 18 tests, one per claim above (P1 2, P2 3, P3 2, P4 1, P5 4, P6 3, P7 3). |

## Not verified (no phone here)

- Not run on a phone. The APK is yours to build (`flutter build apk`).
- Offline picker + offline Get chat with 3 real groups: needs the phone check below.
- Delete locally on a group: needs the phone check.

## Phone checks (5 minutes, then one log)

1. **Server ON**, same Wi-Fi → Conversations opens → open **Group 1** chat and come back (this is what refreshes the group list).
2. **Server OFF** → New request → **Group** → **Pick**: Group 1, Group 2, Group 3 are all there (`PICKER_LIST323 src=saved+chats` or `saved`).
3. Server still OFF → **Get chat** on a group → the request goes out (card + buzz on the other phone), or, if that group's phones were never learned, the log now says `GET_CHAT_FAIL323 why=targets_empty`.
4. A chat with 6 photos → the files card fills; the log shows `FILE_QUEUE_ASKED` (and, if it waits, `FILE_QUEUE_SKIP323 why=…`).
5. Conversations → long-press a group → **Delete locally** → the group is gone; `DELETE_GROUP`/no SQL error in the log.
6. **P6:** with the server off, the Conversations title line shows **"Saved 18:44"** (the time the list was last saved). Turn the server on and open Conversations again — the line goes away.
7. **P5:** with the server off, tap Get chat on a group whose phones this phone never learned → the sheet says **"Server off - this group's phones are not known yet."** (not the old dead end). In Urdu: "سرور بند - اس گروپ کے فون ابھی معلوم نہیں".
8. Share the log. `PICKER_LIST323` + `GROUPS_SAVED323` + `FILE_QUEUE_*` are the lines to look at (a P5 tap adds `GET_CHAT_FAIL323 … words=server_off`).

## Still open from 322 (not part of 323)

W6 (N1–N6 notification checks), S8 `label_current`, W1–W3, the 322 APK checks, and the pre-existing 321 test-clock issue now fixed in the test only (`bundle321_redesign_test`).
