# Bundle 203 — many files with no internet (1:1), files over 50 MB, private lock ring, one ring per file

App only. Version **3.0.45+116**. No database change. No server change.

Zip: `locallink_app_203_2026-11-04.zip` (unzip over the LocalLink folder).

## What changed

| # | Part | What it does |
|---|------|--------------|
| 1 | One flush at a time | Only one "send the queue" runs at a time. If it is asked again while it runs, it runs **once more at the end** (log `MESSAGE_FLUSH_AGAIN`). The watchdog now waits for **90 s with no progress** (log `MESSAGE_FLUSH_WATCHDOG_RESET idle=…`), and the old run stops at its next item (`MESSAGE_FLUSH_STALE_STOP`). Each item is read again before it is sent, so an item that is already finished is skipped. Small files go first. |
| 2 | The phone answers early | The phone's file sender says "accepted" **before** it sends the parts, so the text message is not stuck behind the file bytes. If 8 files are already going, the next one **waits in a line** instead of failing (`FILE_SEND_WAITING`) and starts when a place is free (`FILE_SEND_FROM_LINE`). |
| 3 | Continue, never back to 0 | Each file being sent gets **one fixed open copy** (`attachments/.send-<fileId>.<ext>`, log `DIRECT_FILE_SEND_COPY reuse=…`). The 5-minute sweep leaves it alone. It is deleted when the file is sent or cancelled, when the message is deleted, or after 7 days. The phone also **continues** the same file (same friend, size and fingerprint) if its path changed (`FILE_SEND_CONTINUE`). Groups use the same fixed copy, which is kept for the other members until the 7-day sweep. |
| 4 | No double sends | The phone remembers which files the friend already has (`direct_files_done`, saved; at most 500 files, kept 7 days) and which ones are still on their way (10 minutes). Logs: `DIRECT_FILE_ALREADY_DONE`, `DIRECT_FILE_STILL_SENDING`. "Tap to download" on the other phone clears this memory, so the file is sent fresh. |
| 5 | Files over 50 MB | They are dropped when you pick them (1:1 and group chats) and when you forward them, with a pop-up: "File too big" / "2 files too big", plus the file name and size, and **OK**. Forward: "…can't be forwarded. The other items were forwarded." As a safety net, the send step never sends such a file (`DIRECT_FILE_TOO_BIG_DROPPED`). |
| 5b | Private lock ring | Your **own** picture on **Profile** and on the **Settings card** gets a blue ring and a small white circle with a blue lock, but only while Private profile is ON. It changes as soon as you move the switch. Friends see nothing new. |
| 6 | One ring per file | When a message has several files, each file shows **its own** percent ring. |

## Checks done here
- `flutter analyze`: no new issues. Same as `0f3e1df`, apart from the new files, which are clean.
- Kotlin compile check (`kcheck`): clean.
- Full test suite: **1501 passed, 0 failed** (148 files; new `test/direct_send_203_test.dart`, 22 tests).
- Not tested on a phone yet: the real Nearby transfer, the waiting line and the continue. These are compile and source checks only, so please run the phone tests below.

## Phone tests (Realme = Sajjad, ZTE = Sumaira, internet OFF on both, Nearby/Wi-Fi on)

1. **203-1 Your case:** send 6 photos + 1 video (under 50 MB) and then type 3 texts. ✅ The texts arrive within ~10 s while the files are still going. In the logs there is no `MESSAGE_FLUSH_WATCHDOG_RESET` and no `FILE_SEND_REPLACED`.
2. **203-2 10 photos at once:** ✅ all 10 arrive. Each photo shows its own ring. If more than 8 are sent at once, you see `FILE_SEND_WAITING` then `FILE_SEND_FROM_LINE` in the logs. No photo arrives twice.
3. **203-3 Walk away:** start a ~40 MB video, walk out of range for 1 minute, then come back. ✅ It **continues** from where it stopped (`FILE_SEND_CONTINUE` or the same path with `reuse=true`) and does not go back to 0%.
4. **203-4 Long send (over 5 minutes):** send a big video over a slow link. ✅ It does not restart after 5 minutes (the `.send-` copy is not swept).
5. **203-5 Over 50 MB:** pick a 63 MB video plus 2 photos in a 1:1 chat. ✅ The pop-up "File too big" appears, and only the 2 photos stay. Do the same in a group. Forward a message that has a >50 MB file. ✅ The forward pop-up appears and the other items are sent.
6. **203-6 Tap to download:** on the ZTE, cancel a photo while it is coming, then tap "Tap to download". ✅ The Realme sends it again (the done memory is cleared).
7. **203-7 Online unchanged:** with internet ON, send photos and texts. ✅ Same as before.
8. **203-8 Groups:** in a group with no internet, send 3 photos. ✅ All members get them, and a retry continues instead of restarting.
9. **203-9 Private lock:** Profile › Privacy › Private profile ON. ✅ The ring and lock appear on your picture on Profile and on the Settings card at once. Turn it OFF and ✅ they disappear. On the ZTE, your picture has no ring.

If something fails: tap "Chats" 5 times → share the logs.

## Commit
```
v3 3.0.45 bundle 203: one flush at a time, files answer early + wait line, continue not restart (.send- copy), no double sends, >50 MB pop-up + drop, private lock ring, one ring per file
```
