# TODO 208: everything in PENDING.md section A (code-checked)

- Base: app `0c645bd` (bundle 207, 3.0.48+119). Checked in a fresh clone of that commit.
- New version: **3.0.49+120**. Backend: no change. DB: no new table and no new column (only new SELECT queries).
- Delivery: like 207. One zip after each phase, then the next phase starts by itself. The final zip has everything.
- **"go ahead 208" given 2026-11-05.** Choices: the % ring in the viewer **and** in the chat bubble (D6 = yes); "Waiting for {name}" (E7 = yes); auto-download only the last 7 days.

| Phase | What you get | Size |
|---|---|---|
| A | The 2 tests that fail on your Windows PC pass | small |
| B | Your own photo on "You" in New group | small |
| C | Video pictures show without playing first | medium |
| D | The viewer shows only "45%" in a filling ring (this is also N4) | big |
| E | Every arriving file downloads by itself, offline first | big |
| F | Final checks, APPLY_208.md, zip | – |

---

## Phase A: the 2 tests that fail on Windows

Your run: 1603 pass / 2 fail. Both are mistakes in the tests, not the app.

### A1. `test/bundle207h_test.dart` (line 23)
- **Now:** `addTearDown(() => dir.deleteSync(recursive: true));`. The test shows `profile_avatar_a.jpg` with `Image.file`. On Windows the picture loader still has the file open when the test ends, so the delete fails with errno 32. Linux allows deleting an open file, so it passes here.
- **Do:**
  1. Add a small shared helper `test/support/safe_delete.dart` → `void safeDeleteDir(Directory d)`. It tries `deleteSync(recursive: true)`. On a `FileSystemException` it waits 50 ms and tries once more, then gives up quietly (a temp folder, Windows cleans it later).
  2. Before the end of the test: `await tester.pumpWidget(const SizedBox())` (takes the picture off the screen) + `imageCache.clear()`.
  3. Use `safeDeleteDir` in `bundle207h_test.dart:23`.
- **Same kind of risk, fix too:** `test/bundle180_test.dart:248`, `:264` and `test/chat_media_147_test.dart:228` → `safeDeleteDir`.

### A2. `test/profile_photo_204_test.dart:609` "online after a restart the codes come back from the cards"
- **Now (line 605–609):** `debugLoadPhotoCodes()` starts `ensurePhoto(c)` without waiting for it (`unawaited`, `directory_repository.dart:243`). The test waits a fixed 30 ms, then expects `photoBook.fileFor('ali')` to be there. On a slower PC the download + save takes longer than 30 ms.
- **Do:**
  1. Add a helper in the same file: `Future<void> waitFor(bool Function() ok, {Duration max = const Duration(seconds: 3)})`. It checks every 20 ms and stops when `ok()` is true or the time is up.
  2. Line 606: replace the 30 ms with `await waitFor(() => sara.repo.photoBook.fileFor('ali') != null)`.
- **Look at the other fixed waits in that file:** lines 184, 355, 469, 499, 514, 528, 535.
  - If the next line expects something **to be there**, use `waitFor`.
  - If it expects something **not** to happen (`isEmpty`, `isNull`), keep the fixed wait but make it 150 ms, so a slow PC still has time to do the wrong thing if there is a bug.
- **Check:** run both files 5 times in a row on Linux. You check `flutter test` on Windows.

---

## Phase B: your photo on "You" in New group

- **Now:** `new_group_screen.dart:674` → `const AccountAvatar(name: 'You', radius: 26)`. There is no `localPath` and no `peerId`, so it always shows the letter "Y".
  - `NewGroupScreen` (`:68`) only gets `loadFriends`, `onCreate` and `onGoToPeople`, then pushes `NewGroupNameScreen(people, onCreate)` (`:131`).
  - Settings does it right: `SettingsOwnAvatar` (`messenger_settings_screen.dart:343`) reads `account.cachedProfile().localAvatarPath` and listens to `OwnProfileSignal.changed`.
- **Do:**
  1. `NewGroupScreen` gets a new optional parameter `loadOwnPhoto` (`Future<String> Function()?`, default null = the letter as now). It passes it on to `NewGroupNameScreen`.
  2. `NewGroupNameScreen` calls it in `initState`, keeps `_ownPath` and uses `AccountAvatar(name: 'You', radius: 26, localPath: _ownPath, peerId: ownDeviceId)`. If the file is missing, `AccountAvatar` already falls back to the picture book and then the letter.
  3. `home_screen.dart:1017`: pass `loadOwnPhoto: () async => (await widget.accountRepository.cachedProfile())?.localAvatarPath ?? ''`.
  4. No lock ring here (the lock is only on Profile + the Settings card, rule from 203/207 O).
- **Checked, no change needed:** Group info (`group_info_screen.dart:952`) and the reactions sheet (`group_sheets.dart:477`) already use `peerId: <my device id>` → my picture through the picture book (207 H).
- **Tests:** a widget test with a fake loader → the "You" avatar has `localPath` = the file. Null loader → the letter, as now.

---

## Phase C: video pictures without playing

Why it happens (code):

| # | Where | Problem |
|---|---|---|
| C-a | `attachment_tile.dart:287` `_compactReady` (a grid square, 2+ media in one message, `bubble_media.dart:119`) | uses only `VideoInfoCache.peek(...)`. It never asks for the first frame. Only `ChatVideoPlayer` asks (`chat_video_player.dart:99` → `_loadInfo`), and a grid square never builds a `ChatVideoPlayer`. When a video is played in the viewer the cache fills, and then the square shows the picture. **This is the "only after playing" bug.** |
| C-b | `media_grid.dart:158` `MediaThumbFill` | looks for the saved small picture once (`initState`). The small picture is made a moment later (`_ensureThumb` → `ensureThumb`, one at a time, `media_storage_service.dart:377`). The tile does redraw on the `MediaBook` change (`attachment_tile.dart:110` listener), but `didUpdateWidget` (`media_grid.dart:170`) only loads again when the id changes. So the square stays grey. |
| C-c | `attachment_tile.dart:952` `_videoPlaceholder` (the file is still being locked / opened; with 207 G5 big videos go one at a time, so 5 videos wait a long time) | uses only `peek`. It never uses the small saved picture → a black box. |
| C-d | `VideoInfoCache._read` (`chat_video_controller.dart:345`) | when the native `video_info` fails once (the file is still being written), it returns null and nobody asks again. |
| C-e | `_makeThumb` (`media_storage_service.dart:395`) | `if (inCall()) return false;`. A video that arrives during a call never gets its small picture later. |

- **Do:**
  - **C1 grid square:** in `_compactReady`, when the video `info` is null, start `VideoInfoCache.load(path, _videoCacheKey)` once per tile (a flag, so a redraw doesn't ask again) and `setState` when it comes back. While it waits, show `MediaThumbFill` (the saved small picture) as now.
  - **C2 `MediaThumbFill`:** in `didUpdateWidget`, also load again when `_path == null`. Also listen to `MediaBook.instance` and, when that id's `hasThumb` turns true, call `_load()`. `MediaThumbs.load` already does not cache "nothing found".
  - **C3 placeholder:** `_videoPlaceholder` → when `cached?.thumbnail == null`, show `MediaThumbFill(attachmentId: a.id)` at 55 % like the thumbnail now. This works for my own videos (the small picture exists) and for received ones once it is made.
  - **C4 one retry:** `VideoInfoCache` remembers a failed key with its time. A new `load` for that key after 3 s tries once more, at most 2 tries per key (no loop).
  - **C5 after a call:** when `_makeThumb` skips because of a call, remember `fileId + path` (max 20). When the call ends (the same call-end hook the voice-note queue uses, bundle 179), make them. Check the exact hook name while building.
  - **C6 log:** `THUMB_SHOWN where=grid|placeholder|viewer from=frame|saved` (once per file per run, so the logs don't fill up).
- **What it can't fix:** a received video that has not arrived yet has no picture (there is no file yet). Showing a picture before the file arrives would need the sender to send a tiny picture first. That is not in this phase; ask later if you want it.
- **Tests:**
  - grid square with a fake `video_info` → the picture appears without playing;
  - `MediaThumbFill` grey → `MediaBook.setThumb` → the picture appears;
  - placeholder with a saved small picture → it shows;
  - `video_info` fails once → the second try after 3 s works, and there is no third try.

---

## Phase D: viewer "45%" only (your choice; also N4)

- **Now:** `media_gallery_viewer.dart:485–507`: a white spinner (`CircularProgressIndicator`) + "Preparing…" (`Key('media_gallery_preparing')`) + the small line "Your video · 20 MB · plays in a moment" (`Key('media_gallery_preparing_line')`).
  - The work behind it is `MediaGalleryViewer.prepare` (`:109`): `protectLegacyLocalFile` (lock, only for an old plain file) → `materializeForDisplay` → `SensitiveFileProtectionService.materializeForView` (`sensitive_file_protection_service.dart:88`) → `_decryptFileWorker` (`:224`).
- **Why there is no number today:** `_decryptFileWorker` reads the whole file and calls `AesGcm.with256bits().decrypt(...)` once, in another isolate. That is a single step with nothing in between to count. I checked the package (`cryptography 2.9.0`):
  - `decryptStream` exists, but for AES-GCM in Dart it collects everything and then decrypts at the end (`_DefaultCipherState`), so it would still jump 0 → 100.
  - The GCM pieces it uses inside (`_ghash`, `_calculateMacSync`) are private.
- **Do (my plan, safe):**
  - **D1. Decrypt in parts with real progress, same file format:**
    - New file `lib/core/security/gcm_parts.dart`. It does the same AES-256-GCM as the package, but in 1 MB parts: a check-sum pass over the parts, then an unlock pass over the parts. It uses the same steps as the package code (Apache-2.0 licence, noted in the file).
    - After each part it sends "done bytes / total" to the screen through a `SendPort` from the worker isolate.
    - The file on disk does **not** change (`magic | nonce len | mac len | nonce | mac | cipher text`), so old files open as before.
  - **D2. Safety net:**
    - Tests unlock 40+ files of different sizes (0 B, 1 B, 15/16/17 B, 1 MB ± 1, 5 MB, random) with both the new code and the package. The results must be the same byte for byte. A wrong key or a changed byte must still fail (`SecretBoxAuthenticationError`).
    - If the new code throws anything unexpected (not a bad file / wrong key), the old one-step decrypt runs, log `MEDIA_DECRYPT_PARTS_FALLBACK`.
  - **D3. Lock progress too:** `_encryptFileWorker` gets the same part-by-part version, for the case where an old plain file is locked first (`protectLegacyLocalFile`). The bar counts lock + open as one 0→100 %.
  - **D4. A shared notifier, no change to the files contract:**
    - New `MediaPrepareProgress` (`lib/features/files/data/services/media_prepare_progress.dart`): `ValueListenable<double?> watch(String protectedPath)`, `report(path, done, total)`, `clear(path)`.
    - `materializeForView` / `protectFile` report into it, keyed by the locked file path.
    - `MediaViewCache.acquire` is shared (`_held`), so the chat tile and the viewer see the same number.
  - **D5. The screen:**
    - Replace the spinner + "Preparing…" + the small line with **one ring that fills, with only "45%" in the middle**: `BlueProgressRing` (`blue_progress_ring.dart`), white on the dark page, size 64. Before the first number arrives: the same ring turning with no text (no word).
    - Keys: `media_gallery_prepare_ring`, `media_gallery_prepare_pct`. The old keys `media_gallery_preparing` / `_preparing_line` are removed.
    - Fix the old tests that look for them: `test/bundle207g_test.dart:161`, and check `group_chat_screen_test.dart` / `error_toast_test.dart` (they mention "Preparing…"; see if it is the same widget).
  - **D6. Chat bubble (same number, small):** while a bubble waits for its own file to open (`_prepareExistingPath`), the play button in `_videoPlaceholder` becomes the same small ring with "45%" (only for files > 2 MB; small ones are too quick to see). Question: do you want this in the chat too, or **only in the viewer** like you said? My advice: only the viewer for now (what you asked); the bubble later if you like it.
  - **D7. Logs:** keep `MEDIA_DECRYPT_SLOW ms=`, add `mb=` and `parts=y|n` so we can see the speed on the ZTE vs Realme.
- **Honest limit:** this shows the real progress. It does **not** make the wait shorter (a 30 MB video on the ZTE is still about 15 s). Making it faster would need Android's own built-in AES (Kotlin), which is a separate bigger job; I can plan it later if you want.
- **Memory:** the parts version reads the file in parts, so it uses **less** memory than today (no whole-file `readAsBytes` + whole plain copy). Good for the 2 GB ZTE.

---

## Phase E: every arriving file downloads by itself (offline first)

Your choices: everything, any network; it starts as soon as the file arrives, even when the chat is closed; 1:1 + groups; most users have no internet.

### What the code does now
- **Wi-Fi Direct 1:1:** the sender's phone pushes the file by itself.
  - When the sender presses X → `file_cancelled` → `markCancelled` (`reliable_messaging_service.dart:2317`) → the bubble shows "Tap to download".
  - When I press X → `cancelReceive` (`:188`) → "Tap to download".
  - When the transfer breaks (out of range): the sender has **no** automatic re-send when the friend comes back. `peer_connected` (`:2452`) only flushes acks. `_repushMedia` (`:217`) runs only on a tap (`media_resend_request`, `:279`) or on Resend.
- **Wi-Fi Direct group:** the sender already tries again with waits of 15 s → 15 min, and at once when the member comes near (`GroupFileSend.peerUp`, `group_nearby_files.dart:327`).
  - But the receiver's `GroupFileWatch` (`:533`) marks the file "Tap to download" after 3 min without bytes. The tap sends `need` (resets the sender's tries, max 5 per 10 min, `:285`).
  - A sender row in `stop` (someone pressed X) never goes again without a tap.
  - `GroupFileWatch` is memory only, so after a restart nothing watches.
  - Rule kept: **only the sender sends the file** (your groups rule), no other member.
- **Online:** `_maybeAutoDownload` (`attachment_tile.dart:426`): only photos, voice notes and videos ≤ 10 MB, and **only when the bubble is on the screen**. Documents and bigger files wait for a tap. The download itself saves the path in the DB (`file_transfer_service.dart:183/205` → `setMessageAttachmentLocalPath` / `setGroupAttachmentLocalPath`), and an open bubble picks it up (`didUpdateWidget`, `attachment_tile.dart:365`, `ATTACHMENT_PATH_ARRIVED`).

### What to build
- **E1. New `AutoFetch` service** (`lib/features/files/data/services/auto_fetch_service.dart`). It is started in the same place as the messaging services, so it runs while the app process is alive (Keep running ON), also with the chat closed.
  - It keeps a list of "files I should have": incoming 1:1 + group attachments with no `local_path`, at most 7 days old, ≤ 50 MB (`FileSizeRule.maxBytes`).
  - New store queries, SELECT only, no DB change:
    - `missingIncomingAttachments(since)` on `message_attachments` join `messages`;
    - `missingGroupAttachments(since)` on `group_message_attachments` join `group_messages`.
  - **When it looks:**
    - a new message with files arrives (1:1 `incoming` stream, group `incoming` stream `group_messaging_service.dart:511`);
    - app start;
    - the server connects;
    - a friend / member is seen nearby;
    - every 2 minutes while something is missing.
- **E2. Never auto-start these:**
  1. A file **I** stopped with X. New persistent set `stoppedByMe` (prefs, max 300 ids) in `MediaTransferActions`. Today `cancelled` mixes "I pressed X", "the sender pressed X" and "stalled".
  2. A file removed by Storage clean-up / "Remove" (`MediaBook.isRemoved`). Otherwise the auto clean (K1) and auto-download would fight.
  3. My own files.
  4. During a voice call (the 179 rule: files wait for the call to end), then go on.
  5. Free space < file size + 200 MB (from `storage_stats`, `media_storage_service.dart:158`). Log `AUTO_DL_SKIP why=space`; the bubble keeps its download button.
- **E3. Offline 1:1, the friend comes back:**
  - On `peer_connected` / `route_recovered` for friend X (and the presence "nearby" signal), for each missing file from X that has not moved bytes for ≥ 60 s (`MediaProgressHub` shows the last movement), it sends `media_resend_request` by itself, the same message as the tap (`requestResend`, `:201`).
  - The sender side already limits it to 5 per 10 min (`_resendAsks`, `:281`); my side waits at least 2 min between asks for the same file.
  - The sender pushes again (`_repushMedia` → `media_resend_start`, `directFilesDone.clear`).
- **E4. Offline group, the sender comes back:**
  - When the writer of a stuck group file is seen nearby (the same seen signal as `GROUP_PEER_SEEN_FLUSH`, `group_nearby_service.dart:198`), it sends `sendFileNeed` by itself (`:1100`). The 5-per-10-min limit stays.
  - This also covers a restart: E1 finds the missing files from the DB.
- **E5. Sender side, 1:1** (so it also works with an old receiver): on `file_failed` / `file_expired` for my 1:1 file, remember it (memory + prefs, max 100). When that friend is `peer_connected` again, call `_repushMedia(message, onlyFileId:)` once. Not for `file_cancelled` (a stop by X is respected).
- **E6. Online:**
  - Missing files with a `download_url` download one at a time in the background through the files repository (`downloadForMessage` / `downloadForGroupMessage`), any type, ≤ 50 MB, any network (your choice).
  - Progress goes into `MediaProgressHub` so an open bubble shows the blue ring.
  - On failure it tries again after 1, 5 and 15 min, then waits for a tap.
  - `_maybeAutoDownload` in the bubble: the 10 MB / photo-voice-video limit goes. The bubble asks `AutoFetch` (one download per file, never two at the same time for the same file).
- **E7. The bubble:**
  - A stalled offline file that `AutoFetch` will ask for by itself shows "Waiting for {name}" (small grey text) instead of "Tap to download"; a tap still asks at once.
  - "Tap to download" stays for: the sender stopped it, a 1:1 file the sender can't send again, and online after 3 failed tries.
  - A file I stopped keeps "Tap to download" (no auto).
- **E8. Logs:** `AUTO_DL_START id= way=online|nearby`, `AUTO_DL_DONE id= ms=`, `AUTO_DL_SKIP id= why=mine|stopped|removed|space|call|toobig`, `AUTO_DL_ASK id= to= way=1to1|group`, `MEDIA_REPUSH_AUTO id=`.
- **Questions to settle before building E** (I'll ask with check boxes after "go ahead"):
  1. The "Waiting for {name}" text (E7): yes, or keep "Tap to download"?
  2. Very old missing files: only the last 7 days (my advice), or all?
- **Tests:**
  - `AutoFetch` with fakes: a new message → download starts; a file I stopped → skipped; a removed one → skipped; low space → skipped; during a call → waits, then goes;
  - online → one at a time; peer seen → resend asked once, not again within 2 min;
  - a group writer seen → `sendFileNeed`; the sender side `file_failed` + `peer_connected` → `_repushMedia` once;
  - a restart → missing files found from the DB.

---

## Phase F: finish
- `flutter test` (all, in parts with `run_chunks.sh`); `flutter analyze` compared with 207 (166). No Kotlin change is planned, so no kcheck unless C5/E needs one.
- `pubspec.yaml` → `3.0.49+120`; the version scan in `nearby_190` test.
- `APPLY_208.md`: the change list, checks and phone tests. Update `PENDING.md`.
- One app zip (`mkzip.py`), no PNG, no `local.properties`. Commit line starts with `v3 3.0.49+120 bundle 208: …`.

## Phone tests (planned)
1. **208-1** Windows: `flutter test` → all pass.
2. **208-2** New group → Next: "You" shows your photo.
3. **208-3** Send 3 videos in one message: all 3 squares show their picture within a few seconds, without playing.
4. **208-4** Send 5 big videos: while they get ready, each shows its picture (no black boxes).
5. **208-5** Open a big video in the viewer: only a ring with "12% … 100%", no words; then it plays.
6. **208-6** The ZTE gets a 30 MB video by Wi-Fi Direct with the chat closed: open the chat later → it is already there.
7. **208-7** 1:1: walk out of range halfway through a video, come back: it continues by itself (no tap). Log `AUTO_DL_ASK` / `MEDIA_REPUSH_AUTO`.
8. **208-8** Group: the same as 7 with the writer. Log `AUTO_DL_ASK way=group`.
9. **208-9** Press X on a file: it never starts again by itself; "Tap to download" works.
10. **208-10** Online (both on data): send a 20 MB document: it downloads by itself on the other phone.
11. **208-11** Storage → remove old media: it does **not** download again by itself.
12. **208-12** During a voice call, receive a photo: it comes after the call ends.
