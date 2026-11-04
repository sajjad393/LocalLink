# TODO 203 - Many photos / videos sent while the friend is offline: sends overlap, files restart, files sent twice

Status: **PLAN ONLY - FREEZE ON.** Mock: `mock_203_page1.png` (private lock), `mock_203_page2.png` (50 MB). No code changed. Starts only after you say "go ahead 203".
Found in: `LinkUp-logs-RMX5303-2026-11-04-1719.txt` (Sajjad, Realme, 3.0.41, 1:1 chat with Sumaira).
Code checked at app commit `94274a6` (and the G7 work, which uses the same file code).
Backend: no change. Phone database: no change.

---

## 1. What happened (from your log)

While Sumaira was offline, Sajjad queued 8 messages:

* message 1 (`6e2f`): 2 small photos, a 6.6 MB video and a 4 MB photo;
* message 2 (`e1ff`): 4 photos of about 4 MB each, a 37 MB video and **one file bigger than 50 MB**;
* messages 3-8: voice notes and texts.

At 17:13:14 Sumaira came back on router Wi-Fi (no internet). Then:

| Time | What the log shows |
|---|---|
| 17:13:14 | Send starts with message 1. |
| 17:14:18 | **Safety timer (60 s) fires while the send is still working**: a 2nd send starts. Message 1's photos and its 6.6 MB video go **again from 0**. |
| 17:14:30 | The 4 MB photo was at 71 of 84 parts: **thrown away, starts again from 0** (`FILE_SEND_REPLACED`). |
| 17:14:31 | Message 1 is sent twice by 2 sends at the same time. |
| 17:15:21 | Safety timer fires again: a 3rd send. More photos restart (69/83, 72/82, 73/83). |
| 17:15:57 | The >50 MB file is refused ("direct file size exceeds 50 MiB"). Every retry pushes the other files of message 2 again. |
| 17:16:22 | Safety timer fires a 3rd time: a 4th send. |
| 17:16:33-42 | Message 2 and **the texts + voice notes finally go: about 3.5 minutes after Sumaira came**. They waited behind the big files. |
| 17:16:44 | "too many active outgoing file transfers": the 4 sends filled the file engine (limit 8). |
| 17:17:04 | All messages delivered, nothing left to send. |
| 17:17:13 and 17:17:59 | **Old sends still had their old lists**: messages 2-8 and the voice notes are sent **again**. |
| 16 / 60 / 102 / 199 of 768 | The 37 MB video restarted 4 times. It was still moving when the log ended (17:19:49), never finished in the log. |
| 4 times | The >50 MB file failed each time. **It will never reach Sumaira, not even when the internet comes back** (see Problem 6). |

Not problems: `mali_gralloc`, `MediaCodec`, `Codec2` errors (Realme system noise). "Server returned a reply the
app could not understand" = internet was off.

---

## 2. The problems and their cause in the code

### Problem 1 - The safety timer starts a 2nd send while the 1st is still working
* `reliable_messaging_service.dart` line 912: `_flushWatchdog = 60 seconds`, counted from the **start** of the send,
  not from the last sign of life.
* Lines 1007-1022: after 60 s the next call sets `_flushing = false` and starts a new send.
  **The old send is never told to stop**, so both run.
* Message 1 alone took 77 s (big files), so the timer fired even though everything was working.

### Problem 2 - Old sends keep working from an old list
* Line 1050 reads the queue once; line 1058 walks that list to the end.
* It never checks again whether a message was already delivered or removed. So after 17:17:04 the old sends
  sent delivered messages again.

### Problem 3 - Each try makes a new open copy with a new name, so the file engine starts again from 0
* `_sendablePath` (line 1416) makes a **new decrypted copy every time** (`materializeForView`,
  `sensitive_file_protection_service.dart` line 96: random name `.view-<random>`).
* Native `prepareOutgoingTransfer` (`LocalLinkTransportService.kt` line 4893) continues a file only if the
  **path** is the same. New path = new transfer = progress back to 0 (`FILE_SEND_REPLACED`).
* Hidden risk: these open copies are **deleted after 5 minutes** (`viewRetention`, line 22, swept on app
  start/resume, line 145). A big video that takes more than 5 minutes can lose its copy in the middle of sending
  (native then says `source_changed_or_missing`).
* Extra cost: every try leaves another plain (unlocked) copy on disk until the sweep (37 MB each time for the video).
* G7 (groups, not pushed yet) uses the same copy method (`group_messaging_service.dart` lines 292, 356), so it has the
  same risk.

### Problem 4 - Files the other phone already has are sent again
* When a file is fully received, native forgets it (line 5053, `outgoingTransfers.remove`) and sends `file_sent`.
* Dart only clears the ring on `file_sent` (line 2100). **Nothing remembers "Sumaira already has this file".**
* The message stays in the queue until its "got it" comes back, so every retry pushes all its files again
  (17:14:18: `IMG-...WA0003.jpg` `done=0` after it was already done at 17:13:16).

### Problem 5 - The send waits for each file's bytes, one by one
* Native `sendFileTransportInternal` (line ~808) answers Dart **only after it has written all parts of the file**
  (`sendMissingChunks` runs before `cb(true)`).
* Dart (lines 1117-1160) waits for each file, and only after all files sends the message itself (line 1168).
* Result:
  * the send takes minutes, which fires the safety timer (Problem 1);
  * Sumaira sees the bubble only after all its files were pushed;
  * **texts and voice notes wait behind big videos** (3.5 minutes in your log).

### Problem 6 - A file bigger than 50 MB is lost
* Native refuses it (line 791) and that is right (agreed rule: max 50 MB over Nearby).
* But Dart doesn't know the rule: it tries again on every retry (and pushes the other files again).
* When Sumaira's "got it" for the message comes, the queue row is deleted (line 2562 direct, line 1779 server).
  **The big file then never goes, not even by the server when the internet comes back.**
* Sumaira sees a square for a file that never comes.

### Problem 7 - "too many active outgoing file transfers"
* Native limit = 8 files at once (`DirectFileTransferPolicy.kt` line 8), checked at line 796.
* Today the 9th file just fails. Here it came from the 4 sends at once, but one message with 10 photos can also
  hit it.

### Problem 8 - One ring for all files of a message (small, seen in code)
* The ring is kept per **message** (`MediaProgressHub`, `attachment_tile.dart` line 1252), not per file.
* With 5 files in one message, every square shows the same number, and it jumps between files (80%, then 3%, then 40%).
* Native already sends the file id with each progress (`transfer_id` = file id), so this can be fixed in Dart only.

---

## 3. The fix (my advice)

### Phase 1 - Only one send at a time (Problems 1, 2)
* Every send gets a number. When a new send starts, older ones **stop at the next message** (log
  `MESSAGE_FLUSH_STALE_STOP`).
* Safety timer counts from the **last sign of life**, not from the start:
  * signs of life = starting a message, handing a file, a file progress event, the message going out;
  * it fires only after **90 s with no sign of life** (log `MESSAGE_FLUSH_WATCHDOG_RESET idle=<s>`).
* If a send is asked for while one is running, remember it and run **once more** at the end (log
  `MESSAGE_FLUSH_AGAIN`). So nothing new waits 15 s for the next tick.
* Before each message: read its row again (`store.outboxItem(id)`, already exists). If it's gone, delivered or
  failed, skip it.

### Phase 2 - Messages go first; files go on by themselves (Problems 5, 7)
* Native: answer Dart as soon as the file is **accepted** (checked, saved, "file_queued"), then write the parts on
  the same background thread. The flush no longer waits for bytes.
* Native: when 8 files are already going, the next file **waits in a line** (not an error) and starts when one
  finishes, fails or is cancelled (log `FILE_SEND_WAITING` / `FILE_SEND_FROM_LINE`). The line survives an app
  restart (saved like today's transfers) and is cleared when the file is cancelled.
* Dart: hand all files of a message, then send the message at once. Sumaira sees the bubble with rings straight
  away. Texts and voice notes are no longer stuck behind videos.
* Order stays the same: messages in the order you sent them; small files first inside one message (they finish
  fast).

### Phase 3 - Never restart a file that is already going (Problem 3)
* Dart: one **fixed send copy per file**: `attachments/.send-<fileId><ext>`.
  * Made once and reused while that file is still being sent.
  * Not removed by the 5-minute sweep (new name, its own clean rule).
  * Deleted when the file is done (`file_sent`), cancelled, the message is deleted, or after 7 days.
  * Log `DIRECT_FILE_SEND_COPY reuse=y|n`.
* Native (as a second guard): same file id + same friend + same size + same sha256 = **continue** the transfer and
  just switch the path. Never start from 0 (log `FILE_SEND_CONTINUE`). A really different file still replaces.
* G7: group files use the same fixed copy (one copy per file, shared by all members).

### Phase 4 - Remember files the friend already has (Problem 4)
* On `file_sent` (native says the friend has every part): remember `file id -> friend, time` in a small saved list
  (`writeSetting('direct_files_done', ...)`, no database change). Keep max 500 entries, each for 7 days.
* Before handing a file:
  * already done for this friend: skip (log `DIRECT_FILE_ALREADY_DONE`);
  * still going: skip (native continues it, log `DIRECT_FILE_STILL_SENDING`).
* "Tap to download" from Sumaira (`media_resend_request`, line 243) still sends again on purpose. It removes the
  "done" mark for that file first.

### Phase 5 - Files bigger than 50 MB (Problem 6) - CHANGED by you: "show the message and drop it"
Mock: `mock_203_page2.png` (F1-F5).
* Checked **when you pick files**: 1:1 `chat_screen.dart` `_pickFiles` (line 242) and groups
  `group_chat_screen.dart` `_pickFiles` (line 535). Online or not, the same rule (50 MB = the Nearby limit).
* Any picked file over 50 MB is **dropped before it reaches the review strip**, and a pop-up shows:
  * 1 file: "File too big - This file is bigger than 50 MB, so it was not added." + name + size + OK (F1);
  * several: "2 files too big - These files are bigger than 50 MB, so they were not added." + list (F3);
  * the small files stay in the review strip as today (F2); if all were too big, nothing is added (F3).
* Forward (`forward_screen.dart`): an old file over 50 MB is dropped from the forward, the others go, same pop-up (F5).
* Safety net in the send code: a queued file over 50 MB (e.g. queued by an older version) is skipped, never
  pushed over Nearby again and never retried (log `DIRECT_FILE_TOO_BIG_DROPPED`). The queue row is not kept for it.
* So the "server later" plan is **dropped**: no `server_later`, no partial server copy, no receiver merge check.
* One shared helper `FileSizeRule` (50 MiB, the same number as native `MAX_DIRECT_FILE_SIZE`) + one pop-up widget,
  used by 1:1, groups and forward. The voice note path is not touched (voice notes are always small).
* G7 (if in): the group send rule "max 50 MB per file" is already the same number.

### Phase 5b - Private profile: lock on my picture (new, asked by you)
Mock: `mock_203_page1.png` (L1-L6).
* When **Private profile is ON**: a blue ring (app blue gradient) on the edge of **your own** picture + a small white
  circle with a blue lock sitting on the ring at the top right.
* **OFF**: no ring, no lock (as today).
* Where: your picture on **Profile** (`profile_screen.dart` line 323; the camera button stays at the bottom right) and
  on the **Settings card** (`messenger_settings_screen.dart` line 131). These are the only 2 places your own picture shows.
* Changes at once when the switch moves (Private profile card from bundle 202).
* With a photo: the same ring + lock around the photo.
* Only you see it. Friends see your normal picture (L6, my advice; they already see "Private" on your contact card).
* Code: `AccountAvatar` gets an optional `locked` flag (default off, so all other places stay the same).
* Tests: ring + lock shown only when ON; both places; switch changes it at once; other avatars unchanged.

### Phase 6 - One ring per file (Problem 8, small)
* Rings are kept per message + file. Each square shows its own file. The message ring (used by the single-file
  bubble) shows the total of all files.
* Not a new design: the same rings, just the right number in each square.

### Phase 7 - Tests (here)
* New `test/direct_send_203_test.dart`:
  * a 2nd send while the 1st is running is skipped, then runs once more at the end;
  * the safety timer fires only after 90 s with no sign of life, and the old send stops;
  * a delivered or removed message is not sent again by an old send;
  * a file the friend already has is not handed again; "Tap to download" still sends it again;
  * the same file twice uses the same send copy (same path);
  * picking a >50 MB file: pop-up, file dropped, small files stay; all too big: nothing added; forward drops it;
  * a queued >50 MB file is skipped, never retried;
  * private lock on my picture: Profile + Settings, only when ON;
  * the message goes out before its files finish (fake native answers late);
  * a ring per file: 2 files, 2 different numbers.
* Native: compile check (`kcheck.sh`). The "continue, don't replace" rule and the waiting line go into a small
  policy object that can be checked by reading the code.
* Full suite + analyze.
* `bundle178_test` scans Kotlin for the word `"LocalLink"`, so new log tags must not use it.

### Phase 8 - Zip + APPLY_203.md + phone tests
Phone tests (internet OFF unless said):
1. **203-1 (your case):** Sumaira offline. Sajjad sends 5 photos + a 37 MB video + 3 voice notes + 2 texts.
   Sumaira comes back. Texts and voice notes arrive **within about 10 s**. Photos arrive once each. The video arrives.
   Sajjad's log: no `FILE_SEND_REPLACED`, no `MESSAGE_FLUSH_WATCHDOG_RESET`, no 2nd `MESSAGE_DIRECT_TRANSPORT_SELECTED`
   for the same message.
2. **203-2 Many files:** 10 photos in one message. No "too many active" error. All 10 arrive.
3. **203-3 Walk away:** Sumaira walks away in the middle of the video, then comes back. The video **continues**
   (not from 0).
4. **203-4 Long send:** a video that takes more than 5 minutes (slow mesh). It still finishes (copy not swept).
5. **203-5 Big file:** pick 3 photos + a 60 MB video. Pop-up "File too big", the video is not added, the 3 photos
   send. Same in a group and when forwarding.
9. **203-9 Private lock:** Profile -> Private profile ON: ring + lock on your picture (Profile and Settings).
   OFF: gone. Sumaira's phone: your picture unchanged.
6. **203-6 Tap to download:** cancel a video on Sumaira, then tap it. It is sent again.
7. **203-7 Online:** with internet, the same as before (no change for normal online sending).
8. **203-8 Groups (if G7 is in):** the same case in a group, photos are not sent twice.

---

## 4. Files that change
* `lib/features/messaging/data/services/reliable_messaging_service.dart` - Phases 1, 2, 4, 5, 6
* `lib/features/files/data/services/file_transfer_service.dart` (+ repository + contract) - fixed send copy
* `lib/core/security/sensitive_file_protection_service.dart` - `.send-` copies: own clean rule
* `chat_screen.dart`, `group_chat_screen.dart`, `forward_screen.dart` + new `file_size_rule.dart` - 50 MB pop-up
* `lib/core/widgets/account_avatar.dart`, `profile_screen.dart`, `messenger_settings_screen.dart` - private lock
* `lib/features/files/data/services/media_progress_hub.dart`, `lib/features/files/presentation/widgets/attachment_tile.dart` - ring per file
* `android/.../LocalLinkTransportService.kt` - answer early, waiting line, continue on same file
* `android/.../DirectFileTransferPolicy.kt` - continue / line rules
* If on top of G7: `lib/features/groups/data/services/group_messaging_service.dart` - fixed send copy
* `pubspec.yaml`, `lib/app/local_link_app.dart`, `test/nearby_190_test.dart` - version
* New: `test/direct_send_203_test.dart`, `APPLY_203.md`

Version: 3.0.44+115 if built on top of G7; 3.0.43+114 if built before G7 (then G7 moves up one).

---

## 5. Questions before I start
* **Q1 - Order with G7:** G7 is built but not pushed, and it changes the same files.
  * (my advice) Push G7 first, then 203 on top. One road, no rework, and groups get the same fix.
  * Or 203 first on `94274a6`. Then I rebuild the G7 zip on top of it.
* **Q2 - DONE:** files over 50 MB = pop-up + dropped (your answer). Mock page 2.
* **Q5 - Lock only for you (L6)?** (my advice) yes, friends see no change.
* **Q3 - Ring per file (Phase 6):** (my advice) include it. Or leave rings as they are.
* **Q4 - Sumaira's log:** her ZTE log from 17:13-17:19 would show what she saw (double photos? rings going back?).
  Not needed to start, but good to check.

## 6. Not in 203
* Profile picture over Wi-Fi Direct / mesh + friends see pictures -> its own plan: `TODO_204.md`.
* Block fix (waiting for your go-ahead), video issue (waiting on 193 logs), the 3.1/3.2 items.
* The receiver-side "got it" rules for groups (G7 has its own).
