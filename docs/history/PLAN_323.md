# PLAN 323 — the offline dead ends from 17 Nov (3.0.115+186)

Base: app **322** (`8a06dd1`, 3.0.113+184). Backend: **not touched** (nothing in 323 needs a server change — `b3f3c32` stays).
Spec: `LOG_REVIEW_17Nov_1857.md` §4 (P1–P7). Nothing here is a new screen, row or button. The only UI changes in 323 are the two you approved on 17 Nov: **P5** (honest offline words) and **P6** (one small grey "Saved 18:44" line in the Conversations header while offline).

## The 17 Nov picture in one table

| Complaint | What the log proves | Root cause in 322 |
|---|---|---|
| Get chat on Group 1/2/3 does nothing (server off) | after 18:53:53 **zero** `ADMIN_ACT_MADE` on all 3 phones | `request()` threw at `chat_answer_reader.dart:1219` — `targets` was empty, so `svc.make()` was never reached; **nothing was logged** |
| New request → Group shows only one group | `0` `/admin/groups` calls outside the Admin burst, `0` `GROUPS_LIST` lines | the picker only had the list the picker itself saved; offline it had one row |
| "Delete locally" on a group fails | 18:41:32 / 18:41:39 / 18:42:01 — nothing deleted | `deleteGroupLocal` WHERE clause ended `local_path != ` + `''` → SQLite "incomplete input" → whole `delete_group_tx` rolled back (since 308) |
| Photos never come (files planned, never asked) | 18:45:58 `FILE_QUEUE_PLAN files=6`, card `here=0/6`, **no** `FILE_QUEUE_ASKED` in the hour | the queue counted its own two in-flight asks as "pending cards" as well, so the 3-card window read as full and the ask loop `break`-ed on its first item — with no log line |

## The fixes, and why each is safe

**P1 — the picker is seeded from the saved conversations** (`chat_answer_reader.dart`, `pickerGroups314`)
When the server list is not available, the picker also reads `chatsSavedKey314` group rows (`group_id`, `group_name`, `member_count`) and adds any group the saved server list does not already know. A group the saved server list *does* know keeps that row, because only that row carries `member_devices`. Dedupe by id, `me` still hidden. Nothing on screen changes — the same list, with the groups that were missing from it.

**P2 — the group list stays fresh without the picker** (`_saveGroups323` called from `_chats321`)
`/admin/groups` (+ the server's `nearby` groups) is written to `groupsSavedKey314` on every successful Conversations load — the load that already runs whenever the screen opens. It carries `member_devices`, which is the only thing offline Get chat can ask. A failed fetch logs `ADMIN_GROUPS_LIST323_SKIP` and **never wipes a good list**. `GROUPS_SAVED323 groups=N` on success.

**P3 — the silent exits now say why** (`chat_answer_reader.dart`)
- `PICKER_LIST323 src=server|saved+chats|saved|chats|local known=N shown=N mine=N` — one line per picker open.
- `GET_CHAT_FAIL323 why=targets_empty|same_phone|own|own_devices|already|actions_not_ready` before every throw in `request()`.
No names, no ids except the last 6 of an open request. This is the line that turns the next log into a proof.

**P4 — the delete statement is a statement again** (`local_store.dart`, `deleteGroupLocal`)
`… AND local_path IS NOT NULL AND local_path != ''`. One quote. Locked by a test that reads the SQL, so it cannot silently break again.

**P7 — the file queue asks, and says why when it doesn't** (`file_queue_317.dart`)
`pendingCards` no longer counts a card the queue itself asked (the ids in any plan's `asked` map) — that double-count was what closed the window. And when the loop still leaves without asking, one line per change:
`FILE_QUEUE_SKIP323 why=window on_way=N cards=N left=N` or `why=bytes …`.
The 3-card window, the byte cap, the 322 backoff and the swipe are **unchanged**.

**P5 — honest offline words (built after your yes).** When the server is off and a chat's phones are not known, the app no longer says the dead-end *"This phone doesn't know their phones yet."* It says *"Server off - this group's phones are not known yet."* (or *"…this person's phone…"*). Online the old sentence stays, because there it is true. New words in English + Urdu (`serverOffGroupPhones324`, `serverOffPersonPhone324`), wrapped in RLI/PDI like every other Urdu line, so 304's rules still hold.

**P6 — the saved list says when it was saved (built after your yes).** Every successful Conversations load now stamps `admin_chats_saved_at_314`. Offline, the Conversations header shows one small grey line under the title: *"Saved 18:44"* — or *"Saved 16 Nov 18:44"* when the list is from another day, nothing when this phone never saved one. While the server answers the line is not shown: the list is today's. It is the only new UI in 323 and it is the line you approved.

## What 323 deliberately does not change
Sealing, calls, video, grey bubbles, the 321 status line (blue "files coming" / green "Ready" / grey "N files not available"), 320 Conversations rows and buttons, 318 kept copy, the 322 retry ladder (`fails322` 1→2→5→10 min, max 5), the group outbox, the app never touching Wi-Fi.

## Order of proof
1. `dart analyze` clean on the touched files.
2. New tests `test/bundle323_test.dart` — **18 tests**, one per claim (offline picker, saved group keeps its phones, Conversations saves the group list, offline `resolve314(group)` returns real phones, a failed fetch keeps the old list, `PICKER_LIST323 src=…`, `GET_CHAT_FAIL323 why=actions_not_ready`, queue-made cards don't fill the window, 3 foreign cards still block and log once over 3 ticks, the delete SQL, the P5 words ×3 + the throw site, the P6 stamp + the label ×2 + the header widget test). Full suite: **3443 pass, 0 fail**.
3. Full 346-file suite in chunks; version asserts updated in `bundle223_logs_test` + `nearby_190_test`.
4. One old test was **clock-expired, not broken**: `bundle321_redesign_test` built its file rows at a fixed `2026-11-17T12:01:00Z`; after 12:01 UTC on 17 Nov those rows are older than the plan, the 321 F7 rule calls them old manual cards and skips them. It failed on HEAD too (reproduced). The fixture is now relative to now (+1 min ahead), which is what the rule wants; no product code touched.
