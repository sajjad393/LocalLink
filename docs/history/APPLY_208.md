# APPLY 208: Windows test fixes, your photo on "You", video pictures without playing, "45%" ring when opening, every file downloads by itself (offline first) (app 3.0.49+120)

Base: app `0c645bd` (207, 3.0.48+119; push checked). Backend: no change.
Plan: `TODO_208.md`. Zip: `locallink_app_208_2026-11-05.zip` (app only).
No new table and no new column. Only 2 new SELECT queries.

## A: the 2 tests that failed on Windows
- `test/bundle207h_test.dart`: Windows kept the picture file open when the test ended, so deleting the folder failed (errno 32).
  - Fix: the picture is taken off the screen first, then `imageCache.clear()`, then the new `safeDeleteDir`.
- New `test/support/safe_delete.dart` (`safeDeleteDir`): tries to delete, waits 50 ms, tries once more, then gives up quietly. It is also used in `bundle180_test` and `chat_media_147_test`.
- `test/profile_photo_204_test.dart`: the fixed 30 ms waits are now `_waitFor(...)` (checks every 20 ms, up to 3 s), so a slow PC passes too. "Must not happen" checks now wait 150 ms.

## B: your own photo on "You" in New group
- `new_group_screen.dart`: new `loadOwnPhoto` + `ownPeerId`. "You" shows your profile picture; with no picture it shows the letter, as before.
- `home_screen.dart` passes your saved picture and your device id.

## C: video pictures show without playing first
- **Grid squares** (2+ media in one message): each square now asks for the video's first frame by itself. Before, the picture came only after the video had been played once.
- **`MediaThumbFill`** loads again when the small saved picture is made a moment later (it used to stay grey).
- **While a big video is still getting ready:** the saved small picture shows instead of a black box. If it is not there yet, it says `video_wait_thumb:`.
- **One retry:** when reading the first frame fails (the file is still being written), it tries once more after 3 s. Never more than 2 tries.
- **After a call:** small pictures skipped during a voice call are made when the call ends (max 20, log `THUMB_AFTER_CALL`).
- Log `THUMB_SHOWN where=grid|placeholder|viewer from=frame|saved` (once per file).

## D: only "45%" in a filling ring while a file opens
- **New `lib/core/security/gcm_parts.dart`:** the same AES-256-GCM as before, done in 1 MB parts with a progress count.
  - The file on disk is the same, so old files open as before.
  - Tests check it against the package byte for byte (NIST cases, 44 sizes). A wrong key or a changed byte still fails, and no open copy is left behind.
  - It is also about 2x faster here (8 MB: 445 ms vs 937 ms) and uses less memory, because it never reads the whole file at once.
- **`sensitive_file_protection_service.dart`:**
  - Opening and locking use the parts version with real progress.
  - Before first use it runs a self-check. If the parts version fails for any reason other than a bad file or a wrong key, the old way runs.
  - Logs: `MEDIA_DECRYPT_SLOW` / `MEDIA_ENCRYPT_SLOW` now include `mb=` and `parts=y|n`.
- **New `media_prepare_progress.dart`:** one shared number per file. Locking counts as 0–50 % and opening as 50–100 %.
- **New `prepare_ring.dart` (`PrepareRing`):** a blue ring on a dark circle with only the number, for example "45%". It turns with no text until the first number comes. No words anywhere.
  - **Viewer:** "Preparing…" and the small line under it are gone; only the ring shows (64 px).
  - **Chat bubble:** while my own saved video (over 2 MB) is being opened, the play button becomes the same small ring (56 px).

## E: every file that comes to me downloads by itself (offline first)
- **New `lib/features/files/data/services/auto_fetch_service.dart` (`AutoFetch`):**
  - It starts together with the messaging services, so it runs while the app runs (Keep running ON), also when the chat is closed.
  - It looks at app start (after 20 s), when a new message with files comes, when the server connects, when a friend or member is seen Nearby, and every 2 minutes while something is missing.
- **What it gets:** files from the last 7 days that are not on the phone yet, up to 50 MB, in 1:1 chats and groups.
  - New store SELECTs: `missingIncomingAttachments` and `missingGroupAttachments`. Deleted or cleared messages are left out.
- **Never by itself:**
  - my own files;
  - a file I stopped with X (saved in settings, kept after a restart, max 300);
  - a file the sender stopped with X;
  - a file removed by Storage clean-up;
  - anything over 50 MB or older than 7 days.
- **Waits or skips:**
  - During a voice call it waits, then goes on.
  - With less free space than the file + 200 MB, it skips (log `why=space`).
- **Offline 1:1 and groups (E3/E4):**
  - When a file has not moved for 60 s and the sender is seen Nearby (`peer_connected`, `route_recovered`, `peer_discovered`, `relay_connected`, or presence says Nearby), it asks the sender's phone to send the file again.
  - This is the same request as tapping "Tap to download": 1:1 = `media_resend_request`, group = `need`.
  - At least 2 min between asks for the same file. The sender's own limit (5 per 10 min) stays.
  - Only the sender sends a group file, as before.
- **Sender side (E5):** when my 1:1 file breaks on the way (`file_failed` / `file_expired`), the phone remembers it (saved, max 100) and sends it once more when that friend connects again (log `MEDIA_REPUSH_AUTO`). A file stopped with X (`file_cancelled`) is never sent again by itself.
- **Online (E6):**
  - Files with a server link download one at a time in the background, any type, up to 50 MB.
  - The bubble shows the blue ring with % and X. X stops the file and it is remembered.
  - If a download fails, it tries again after 1, 5 and 15 min, then waits for a tap.
  - A tap puts the file first in line. The same file is never downloaded twice at the same time.
  - An open bubble shows the file as soon as it is saved.
  - On screen, a bubble still asks at once for its own small photo, voice note or video (≤ 10 MB, any age) through the same line.
- **The bubble (E7):**
  - A stuck Nearby file shows a clock and **"Waiting for Sajjad"** (small grey text). A tap asks at once.
  - "Tap to download" stays for a file I stopped and a file the sender stopped.
  - When bytes move again, the ring comes back.
- **Logs:** `AUTO_DL_SERVICE_START`, `AUTO_DL_START id= way=online size=`, `AUTO_DL_DONE id= ms=`, `AUTO_DL_FAILED try=`, `AUTO_DL_STOPPED`, `AUTO_DL_SKIP id= why=mine|stopped|sender_stopped|removed|space|call|toobig`, `AUTO_DL_ASK id= to= way=1to1|group`, `MEDIA_REPUSH_REMEMBER`, `MEDIA_REPUSH_AUTO`, `MEDIA_RESEND_IGNORED why=stopped`.

## Other
- `pubspec.yaml` 3.0.49+120; version stamp "v3 · 3.0.49 · bundles 104-208 + groups G1-G7"; the `nearby_190` scan.
- New tests:
  - `bundle208b_test` (4)
  - `bundle208c_test` (7)
  - `bundle208d_test` (12)
  - `bundle208e_test` (26)
- Updated tests:
  - `bundle207g_test`: the viewer shows the ring, no words.
  - `bundle180`, `chat_media_147`, `bundle207h`, `profile_photo_204`: Windows-safe.

## Checks done here (no phone)
- Flutter tests: **1654 / 1654 pass** (159 test files, the full suite, run on the final code).
- `flutter analyze`: **166 issues, the same as 207; no new ones** (the one new lint note was fixed).
- No Kotlin change, no DB change, no backend change.
- Honest limits:
  - The "45%" ring shows real progress, but it does not make a big file open faster on the ZTE. The parts code is about 2x faster here; the phone will show the real speed (`MEDIA_DECRYPT_SLOW ... parts=y`).
  - A received video that has not arrived yet has no picture yet.
  - Auto-download works only while the app process is alive (Keep running ON).

## Phone tests
1. **208-1** Windows: `flutter test`: all pass.
2. **208-2** New group → Next: "You" shows your photo.
3. **208-3** Send 3 videos in one message: all 3 squares show their picture within a few seconds, without playing.
4. **208-4** Send 5 big videos: while they get ready, each one shows its picture (no black boxes).
5. **208-5** Open a big video in the viewer: you see only a ring with "12% … 100%" and no words, then it plays. The same small ring shows on the bubble.
6. **208-6** The ZTE gets a 30 MB video by Wi-Fi Direct with the chat closed. Open the chat later: it is already there.
7. **208-7** 1:1: walk out of range halfway through a video, then come back: it continues by itself, with no tap. The bubble shows "Waiting for …" while you are away. Logs: `AUTO_DL_ASK` / `MEDIA_REPUSH_AUTO`.
8. **208-8** Group: the same as 7 with the writer. Log `AUTO_DL_ASK way=group`.
9. **208-9** Press X on a file: it never starts again by itself, and "Tap to download" still works.
10. **208-10** Online (both phones on data): send a 20 MB document. It downloads by itself on the other phone.
11. **208-11** Storage → remove old media: it does **not** download again by itself.
12. **208-12** Receive a photo during a voice call: it comes after the call ends.

Logs after testing: 5 taps on "Chats" on both phones.

## Commit
`v3 3.0.49+120 bundle 208: Windows test fixes, own photo on You, video pictures without playing, 45% ring when opening (2x faster unlock), auto-download every file offline first (1:1 + groups, last 7 days), Waiting for name`
