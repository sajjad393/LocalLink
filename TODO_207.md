# TODO 207: no gray press overlay, close the video at the end, tap a reaction to add yours

> **Status (2026-11-05):** "go ahead 207" given, then the user said **"keep freeze on"** and stopped the build before the zip. The code is written and the tests pass, but there is **no zip yet**. Work is saved in `/home/user/p207_wip/`. Split into phases in §Phases. **New points added the same day: PART 2 (phases 207-F..N), code-checked in detail**, plan only, no code yet.
> P1 choice confirmed by the user. P2 and P3 follow my advice.

## P1: no gray overlay on the floating buttons
- **Now:** `lib/core/widgets/brand_gradient_fab.dart` is a `FloatingActionButton` with a transparent background and a gradient `Ink` circle. Pressing or holding it shows the gray highlight/splash. Since 206, holding is how you move the button, so the gray shows every time.
- **Fix:**
  - The highlight, splash, focus and hover colours become transparent (`NoSplash`).
  - A short shrink to 95 % on press, so a tap still feels like a tap.
- **Buttons:**
  - Chats "New conversation", Calls "New call", People "Add contact" (all `BrandGradientFab`).
  - The square buttons in the group screens: Next / Create on "New group" (`SquareGradientFab`, `new_group_screen.dart` ~777).
  - The small "Jump to latest" button in a chat (`chat_screen.dart` ~1174).
- **User choice (2026-11-05):** no gray; the button shrinks to 95 % for a moment on press.
- **Test:** hold any of them: no gray circle or square.

## P2: the video player closes when the video ends
- **Full player** (`ChatVideoFullscreen`, `chat_video_player.dart` ~793):
  - **Now:** it stays on the last picture.
  - **Fix:** at the end it closes (`pop(FullscreenExit.close)`). You're back in the chat, or in the photo viewer, and the bubble shows the preview + play button.
- **Small floating player** (`chat_video_hub.dart` ~583):
  - **Now:** it waits 5 s with a replay button, then closes.
  - **Fix:** it closes at once.
- **Android floating window** (PiP, over other apps):
  - **Fix:** at the end it closes the window. This needs a new `closePip` method in `ChatVideoPip.kt`, using `moveTaskToBack`; the app stays in the background.
- **Not affected:** pausing, or dragging the bar to the end while paused (only a real "played to the end" closes it). Video calls are not touched.
- **Log line:** `VIDEO_END_CLOSE where=full|mini|pip`.

## P3: tap a reaction under a message to add yours (+1)
- **Now:**
  - 1:1 chat: the chips (`message_bubble.dart` `_reactionCounts`) can't be tapped.
  - Group: a tap opens the "who reacted" sheet (`group_chat_screen.dart` `_showReactions`).
- **Fix (1:1 and groups):**
  - Tap ❤️ 1, and you add your ❤️: ❤️ 2.
  - Tap it again, and your ❤️ is removed: ❤️ 1 (like WhatsApp).
  - If you had 👍, tapping ❤️ changes yours to ❤️ (one reaction per person, as now).
  - Your own chip gets a light blue border, so you can see which one is yours.
  - The "who reacted" sheet in groups moves to **holding** the chip.
  - Taps don't work while selecting messages.
  - Admins-only group: a member who can't post gets the same "can't send" note when adding (removing still works).
- **Sending:** uses the existing `react(...)` and the remove path (an empty emoji). It works offline, the same as reacting from the menu.
- **Log line:** `REACTION_TAP add|remove|change`.
- **Found while building:** a 1:1 reaction could not be removed at all before (only groups could). 207 adds 1:1 removal the same way groups do it (an empty emoji note), so update both phones.

## Phone tests
1. **207-1** Hold the Chats, Calls and People buttons and "Jump to latest": no gray. A tap still opens them.
2. **207-2** Play a video full screen to the end: it closes by itself.
3. **207-3** Play it in the small floating player to the end: it closes at once.
4. **207-4** Video in the Android floating window over another app, to the end: the window closes.
5. **207-5** Pause near the end and drag the bar: it does not close.
6. **207-6** 1:1 chat: friend reacted ❤️. Tap ❤️: ❤️ 2 on both phones. Tap again: ❤️ 1.
7. **207-7** Group: tap a chip to add or remove yours; hold the chip to see the "who reacted" list.


## Phases (from APPLY_207.md)

> Freeze on: nothing more is changed until you say "go ahead" for a phase (or for all of 207).
> Each phase can ship alone. If 1–3 ship together, it's still one zip and one commit.

### Phase 207-A: no gray overlay on the floating buttons
- **What:** no gray when you press or hold. The button shrinks to 95 % while your finger is down. A tap still works, and hold-to-move (206) still works.
- **Buttons:** Chats / Calls / People (round), Next / Create on "New group" (square; the grey "off" one doesn't shrink), "Jump to latest" in a chat.
- **Files:** new `lib/core/widgets/no_gray_press.dart`; `brand_gradient_fab.dart`, `new_group_screen.dart`, `chat_screen.dart`.
- **Status:** code written; tests pass (4 in `bundle207_test`).
- **Phone test:** 207-1.

### Phase 207-B: the video player closes when the video ends
- **What:** a video that was **playing** reaches its end:
  - full player: closes, and the bubble shows the preview + play button;
  - small floating player: closes at once (it used to wait 5 s);
  - Android floating window: the window closes and the app stays in the background.
- Pausing near the end and dragging the bar to the end does **not** close it.
- **Log line:** `VIDEO_END_CLOSE where=full|mini|pip`.
- **Files:** `chat_video_hub.dart`, `ChatVideoPip.kt` (new `close`), `test/support/chat_video_fakes.dart`, `chat_media_147_test.dart` (the mini player now closes at once).
- **Status:** code written; tests pass (7 in `bundle207_test` + `chat_media_147`). **Not done:** the Kotlin compile check (`kcheck.sh`).
- **Phone tests:** 207-2, 207-3, 207-4, 207-5.

### Phase 207-C: tap an emoji under a message
- **What (1:1 and groups):**
  - tap ❤️ 1 → ❤️ 2 (yours added);
  - tap your own again → removed;
  - you had 👍 and tap ❤️ → yours changes to ❤️;
  - your own emoji has a light blue border.
- **Groups:** "who reacted" moves to **holding** the chip. In an admins-only group a member gets the "can't send" note when adding.
- **New for 1:1:** removing a reaction (it wasn't possible before). Sent as a hidden note with an empty emoji, the same as groups. An older app ignores it, so update both phones. No database change.
- **Log line:** `REACTION_TAP add|remove|change chat=1to1|group`.
- **Files:**
  - new `lib/core/widgets/reaction_chips.dart`;
  - `message_bubble.dart`, `group_message_bubble.dart`, `chat_screen.dart`, `group_chat_screen.dart`;
  - `chat_bloc.dart` (`removeReaction`), `reliable_messaging_service.dart` (send + receive remove), `local_store.dart` (`deleteMessageReaction`);
  - `group_chat_screen_test.dart` (hold = who reacted + a new tap test).
- **Status:** code written; tests pass (4 in `bundle207_test` + 2 group tests).
- **Phone tests:** 207-6, 207-7.

### Phase 207-D: finish and deliver (after "go ahead")
1. Version 3.0.48+119 + version stamp + `nearby_190` scan. **Done** (in the wip copy).
2. Full test suite. **Done:** 1555 / 1555 pass (151 files).
3. `flutter analyze` diff against 206. **Not finished** (stopped). The partial check showed no new issues in the changed files.
4. Kotlin compile check of `ChatVideoPip.kt`. **Not done.**
5. Zip `locallink_app_207_<date>.zip` + `APPLY_207.md` + commit line + PowerShell. **Not done.**
- If only some phases are approved, the zip leaves out the files of the others. They don't share files, except `chat_screen.dart` (A and C) and the test file (split per phase).

### Phase 207-E: phone tests (you)
- 207-1..7 (list above). Logs: 5 taps on "Chats".

---

# PART 2: new points (2026-11-05), checked in detail against the code + UI

> **FREEZE ON.** This is the plan only; no code has been changed for these points. Each phase needs your "go ahead" (all, or e.g. "go ahead 207-F").
> **Checked against:** the 207 work copy (206 `8e7f0ab` + 207 A–C), the logs from both phones (3.0.46, 00:29–01:30), and your 12 screenshots.
> **Your choices:**
> - Enter = new line.
> - Redo all the screens you named, **mock first**.
> - Poll = one answer, can change for 3 min after voting.
> - Viewer video = full screen, plays by itself.
> - Search = **both** (Chats tab + inside the 1:1 chat).

## Order of work (after "go ahead")
1. **Fixes:** 207-F → G → H → N (bugs found in the logs).
2. **Small changes:** 207-J → K → I → L.
3. **Screens:** 207-M1 + 207-O (PNG mocks, wait for your OK) → 207-M2 + 207-O code (like the mock).
4. **Delivery:** 207-D (full tests, analyze, Kotlin check, zip) → 207-E (phone tests 207-1..20).

- **Version:** 3.0.48+119 stays (one bundle, one zip, one commit).
- **No database change.** No backend change.
- **Older phones:** A phone without 207 still works with one that has it (details in each phase).

---

## Phase 207-F: adding someone to a group is slow (sumaira took ~20 min)

### What happened (logs)
| Time | Realme (you) | ZTE (sumaira) |
|---|---|---|
| 00:29:58 | group "Office" made, card sent (`GROUP_NEARBY_SEND kind=card try=1 ok=true`) | – |
| 00:30:53 / 00:32:14 / 00:34:13 | (re-tries, not logged) | got the card 3 times, **ignored it, no log line**; this phone still had an **older build** |
| 00:35:09 | – | app updated to 3.0.46 (`APP_LAST_EXIT reason=app_updated`) |
| 00:35 → 00:50 | **no new try for ~16 min** | waiting, Nearby the whole time (`peer_discovered transport=lan` every ~4 s) |
| 00:50:17 | try again | `GROUP_CARD_APPLIED v=1 new=true` at once |
| 00:50:18 | 23 waiting messages (hello, poll, votes) go out together | – |

### Why (code)
1. **Retry gaps grow too large:** `group_nearby_service.dart` `_backoffSeconds = [15, 30, 60, 120, 300, 600, 900]`. After 5 tries the next try is 5, 10, then 15 min away, even when the friend is right there.
2. **"Friend came near" only listens to `peer_connected` / `route_recovered` / `relay_connected`** (`handleEvent`, ~line 680). On the same Wi-Fi router the event is `peer_discovered`, which does **not** trigger `flush(peerId:)` or `catchUpWith`. So being Nearby didn't speed anything up.
3. **Messages wait behind the card:** `_flushOnce` skips every message for a member while their card is waiting (`waitingCard`). That is correct, but with (1) and (2) everything waited ~20 min with the clock icon.
4. **Silent drops:** in `handleEvent` / `handlePacket` / `applyCard`, several `return`s log nothing (`sealed != true`, `mesh_final_recipient == false`, `isBlocked`, `_keyOk` false). That's why we can't see why the old build ignored it.
5. **Retries are not logged:** `GROUP_NEARBY_SEND` is only logged for try 1 or a failure, so the log hides the gaps.
6. **The UI says "Waiting · added when Nearby or Online"** even while she shows as Nearby (`group_nearby_widgets.dart` ~171).

### Fix
- **F1, Nearby = send now:** treat `peer_discovered` (and `MESSAGE_ROUTE_AVAILABLE` for that peer) like `peer_connected` for groups. Call `flush(peerId:)` + `catchUpWith(peer)`, **at most once every 20 s per friend** so the 4-second events don't flood.
- **F2, short gaps while Nearby:** if the member is Nearby now (PresenceHub), cap the wait at **20 s** for a card and 60 s for messages. The long gaps (5–15 min) only apply when they are away.
- **F3, ask after an update or open:** when the app starts or opens, send a small "anything for me?" (`group_need`, which already exists) to Nearby friends who are group admins. The card comes straight away.
- **F4, log every drop:** `GROUP_PACKET_DROPPED why=not_sealed|not_final|blocked|bad_key|bad_card|not_friend` (once per reason per minute).
- **F5, log retries:** `GROUP_NEARBY_SEND` also for try 2, 3, 5, 10 (`kind`, `try`, `next_s`).
- **F6, words in the sheet and banner:** if Nearby, "Adding… · Nearby now" with a small spinner. If away, "Waiting · added when Nearby or Online". (The new look itself is in 207-M.)
- **Older phones:** nothing new on the wire; F3 uses the existing `group_need`.

### Files
- `lib/features/groups/data/services/group_nearby_service.dart` (handleEvent, _flushOnce, backoff, logs);
- `lib/features/groups/data/services/group_messaging_service.dart` (start-up ask);
- `lib/features/groups/presentation/widgets/group_nearby_widgets.dart` (texts).

### Tests
- `peer_discovered` triggers a flush for that member (throttled to 20 s);
- the gap stays ≤20 s while Nearby;
- every drop path writes `GROUP_PACKET_DROPPED`;
- the sheet text changes when Nearby.

**Phone test 207-8:** make a group with a Nearby friend. They're in within ~10 s, and the first message gets ✓✓ (no clock).

---

## Phase 207-G: my own group video shows "Not downloaded yet" + screen freezes

### What happened (logs, Realme 01:20–01:23)
- 5 videos (29.9 / 36.2 / 24.3 / 3.4 / 19.4 MB) were sent to Office (`GROUP_FILE_QUEUED files=4` + 1).
- Each video was locked (encrypted on the phone) **while the chat tile, the grid and the viewer all tried to do it at once**: `MEDIA_ENCRYPT_SLOW` 11–23 s each.
- 01:21:15–24: `ATTACHMENT_PREPARE_FAILED` ×7: `PathNotFoundException: Cannot delete file …/attachments/outbox-….mp4` and `Bad state: local file does not exist`.
- One `FILE_SEND_PARTS_FAILED` (IllegalStateException) on the 36 MB video. The file was being locked and removed **while it was still being sent**; it then finished.
- `MAIN_STALL` 1.7 s / 5.8 s / 6.3 s: the screen froze.
- Screenshot 01:22: "5 of 5 · Not downloaded yet" on **your own** video.

### Why (code)
1. `file_transfer_service.dart` `protectLegacyLocalFile()`: no lock. Two callers both see the plain file, both write the same `.enc`, the first deletes the plain file, and the second fails on `file.delete()`. Two writers on one `.enc` can also **damage** the file.
2. `attachment_tile.dart` `_prepareExistingPath()` (~line 443) calls it from every tile instance. The new `.enc` path is only kept in that tile's state (`setState(_localPath)`), **not saved**, so other screens keep trying the old plain path.
3. `media_gallery_viewer.dart` `GalleryItem.fromAttachment` only uses a view that a chat tile **already opened** (`MediaGalleryRegistry.of(id)`). If none is there (tile failed or scrolled away), the page shows "Not downloaded yet" (~line 343), even when the file is on the phone.
4. The plain outbox file can be locked while the group file send is still reading it.

### Fix
- **G1, one job per file:** in `protectLegacyLocalFile`, a shared `Map<path, Future<String>>`. A second caller waits for the same job. Write to `<path>.enc.part`, then rename to `.enc`. Delete the plain file only if it's still there (no error if it's already gone).
- **G2, save the new path:** after locking, call `setMessageAttachmentLocalPath` / `setGroupAttachmentLocalPath` so every screen uses the `.enc`.
- **G3, don't lock a file that is being sent:** skip locking while that file has an active outbox or transfer (`outbox-*` with a pending group/1:1 send). Lock it after `GROUP_FILE_SENT` / `file_sent`.
- **G4, the viewer opens files itself:** if there's no ready view but the file is on the phone, the viewer page decrypts it (off the screen thread) and shows "Preparing…" with a spinner. "Not downloaded yet" + a Download button only when the file is really not on the phone.
- **G5, no freezes:** move the sync read seen in `MAIN_STALL` (`Linux.readBytes` while opening) to the background, and lock at most 1 big file at a time (a queue).
- **Older phones:** no wire change.

### Files
- `lib/features/files/data/services/file_transfer_service.dart`;
- `lib/features/files/presentation/widgets/attachment_tile.dart`;
- `lib/features/files/presentation/widgets/media_gallery_viewer.dart` (+ `media_grid.dart` registry);
- `lib/features/groups/data/services/group_file_*` (sending check).

### Tests
- 3 calls at once on the same file → 1 encrypt, 3 same results, no error;
- after locking, the row has the `.enc` path;
- the viewer with no registry view but a local file → "Preparing…", then plays;
- a file with a pending send is not locked.

**Phone test 207-9:** send 5 big videos to a group and open them right away. All play, none says "Not downloaded yet", and the screen doesn't freeze.

---

## Phase 207-H: a new profile picture doesn't show in Settings or for friends

### What happened
- **Your test:** the new picture shows in Profile and Account, but not on the Settings card, and friends keep the old one or the letter.
- **Logs:** the ZTE asked for your picture **9 times** (`PEER_PHOTO_ASK to=da19f3`, 01:13–01:29). The Realme got all 9 (`DIRECTORY_PHOTO_NEED`) but logged **nothing**: no `PEER_PHOTO_SENT`, no `REFUSED`.

### Why (code)
1. **Settings card:** `messenger_settings_screen.dart` `SettingsOwnAvatar` shows `AccountAvatar(peerId: store.deviceId)`, i.e. your picture from the **friends' picture book** (`PeerPhotoBook`), **not** your profile file (`localAvatarPath`) like Profile and Account do. The book only gets your new picture through `publishOwnProfile → _buildOwnProfile → _ownPhotoFile → setOwn`, and `_buildOwnProfile` returns early (null) when the user id is empty (phone-only account). The Settings screen is also a `StatelessWidget` that never reloads when you come back from Account.
2. **Friends:** `directory_repository.dart` `_handlePhotoNeed` (~line 270) **returns silently** when the asked code isn't your current one (`own.code != message['code']`), when your file isn't found (`own == null`), or when the rate limit says no (`_photoGives.allow`). The friend asked with your **old** code, so it got nothing and kept asking.
3. **Your new picture code reaches friends only through `publishOwnProfile` → `broadcast`** (best effort, no retry). The ZTE showed `DIRECTORY_REPLY_NO_ROUTE` ×10, so cards didn't always get through.

### Fix
- **H1, Settings shows your real picture:** use `localAvatarPath` first (like Account), then the book. Make the card reload when you come back from Account, and listen to a small "my profile changed" signal.
- **H2, update right away on save:** `account_repository.saveProfile` (or the profile screen) calls `PeerPhotoBook.setOwn(...)` directly with the new bytes (or `null` on Remove photo), so Settings, group "You" rows and the poll faces change at once, even if `_buildOwnProfile` can't run.
- **H3, tell friends with a retry:** after a picture change, send your signed card **directly to each friend** (Nearby link and Online), not only by broadcast. Retry when that friend is next seen (like the friend-link resend).
- **H4, an old ask gets the new card:** in `_handlePhotoNeed`, if the asked code is old, send back your **current signed card**. The friend then asks again with the new code and gets the picture.
- **H5, log every skip:** `PEER_PHOTO_SKIPPED why=old_code|no_file|limit|not_started`.
- **Older phones:** no wire change (the card and photo messages already exist).

### Files
- `lib/features/home/presentation/screens/messenger_settings_screen.dart`;
- `lib/features/account/data/repositories/account_repository.dart`;
- `lib/features/account/presentation/screens/profile_screen.dart`;
- `lib/features/directory/data/repositories/directory_repository.dart`;
- `lib/features/directory/data/peer_photo_book.dart`.

### Tests
- after save, the Settings avatar shows the new file;
- an old-code ask → the current card is sent;
- each skip reason is logged;
- Remove photo → the letter shows in Settings at once.

**Phone test 207-10:** change your picture. Settings shows it at once, and the friend's Chats list and chat show it within ~30 s when Nearby.

---

## Phase 207-I: video in the media viewer is a small card, not full screen

### What happened
Screenshot 01:22:13 ("You · 1 of 5"): the video is a small rounded card (0:39, 28.6 MB) with a big play button in the middle of a black screen.

### Why (code)
`media_gallery_viewer.dart` `_page()` (~line 368) draws a video as the **chat bubble tile** inside `Padding(vertical: 72) → FittedBox → MediaTileLook → ChatVideoPlayer` (the inline player). So it's a small card. Tapping play then plays it inline in the card, or opens the full player on top.

### Fix (your choice: full screen + plays by itself)
- **I1:** a video page fills the screen like a photo page: black background, the video keeps its shape (`AspectRatio`, fit contain), no card or rounded corners.
- **I2:** it **starts playing** when you swipe to it and **pauses** when you swipe away (page change). Only one plays at a time (the existing `MediaPlaybackCoordinator`).
- **I3:** tap = show or hide the controls (play/pause, seek bar, time, mute) for 3 s. The top bar ("You · 1 of 5") and the thumbnail strip hide with them, like WhatsApp.
- **I4:** at the end it **stops on the last frame with a replay button**. It does **not** close the viewer (207-B closing only applies to the chat player, the mini player and PiP).
- **I5:** while the file is still being prepared (207-G), show "Preparing…" over the thumbnail.

### Files
- `lib/features/files/presentation/widgets/media_gallery_viewer.dart`;
- `chat_video_player.dart` (a "page" mode using the same controller);
- `media_playback_coordinator.dart`.

### Tests
- a video page is full size (not a `MediaTileLook`);
- it plays on show and pauses on swipe;
- it stops at the end without popping the viewer.

**Phone test 207-11:** open a chat's media and swipe to a video. It fills the screen and plays; swipe away and it pauses.

---

## Phase 207-J: keyboard Enter = new line

### Why (code)
Both chat boxes have `textInputAction: TextInputAction.send` + `onSubmitted: onSend`:
- `chat_composer.dart` ~line 119;
- `group_composer.dart` ~line 66.

So the keyboard shows a Send key instead of Enter.

### Fix
- `textInputAction: TextInputAction.newline` + `keyboardType: TextInputType.multiline`; remove `onSubmitted`.
- The box grows up to 5 lines, then scrolls. Send only with the send button.
- The 1:1 and group chats are the same. Search boxes and the group name box stay as they are.

### Files
`chat_composer.dart`, `group_composer.dart`.

### Tests
The text field has the newline action, and Enter doesn't call send.

**Phone test 207-12:** type "hi", press Enter, type "there". You get 2 lines, and the message is sent only with the button.

---

## Phase 207-K: polls: one answer, change allowed for 3 minutes after voting

### What happened
- Your poll "Tomorrow office or work form home" was made with **"select one or more"**, so both options were ticked.
- Votes sheet: "You" under Office and Home, "1 of 2 voted".
- Logs: 25 `GROUP_VOTE` lines in a few seconds (fast taps). **Each tap was sent as its own group message**; 23 went out together at 00:50.

### Why (code)
- `group_extras_widgets.dart` (New poll sheet) has a `poll_multi` switch ("allow many answers", ~line 342).
- `group_extras.dart` `GroupPoll.multi`, `GroupPollTally.tap()`.
- `group_messaging_service.dart` `vote()` queues one message per tap.
- `GroupVote` has `at` (time of this vote) but no "first vote" time, so a lock can't be checked.

### Fix
- **K1:** remove the `poll_multi` switch. New polls are always "Poll · select one". Old polls that allowed many answers still work as before.
- **K2:** tapping another option **moves** your vote. Tapping your own option takes it back (only within the 3 min).
- **K3, the 3-minute rule:** the vote note gets a new field `f` = time of my **first** vote on this poll (`llvote:v1:{p, c, at, f}`).
  - Every phone ignores a note where `at − f > 3 min` (`GroupExtrasBook.applyVote`), and keeps the earliest `f` it has seen for that voter.
  - So all phones end up with the same result.
- **K4, what you see:**
  - under the poll, "You can change your vote for 2:41" (counts down);
  - after 3 min, "Your vote is final", and tapping does nothing (a short note "Votes can't be changed after 3 minutes").
- **K5, fewer messages:** wait **1.5 s** after the last tap and send only the latest vote (a waiting vote replaces the earlier one in the outbox).
- **K6, Votes sheet:** don't show "You · You": show your name once, with the time on the right.
- **Older phones:** they ignore `f` and still show the votes. A phone without 207 could still change a vote late, but phones with 207 ignore that late change.

### Files
- `lib/core/models/group_extras.dart`;
- `lib/features/groups/data/group_extras_book.dart`;
- `lib/features/groups/data/services/group_messaging_service.dart`;
- `lib/features/groups/presentation/widgets/group_extras_widgets.dart`.

### Tests
- no multi switch;
- tap B after A → only B;
- a change at 2:59 → accepted, at 3:01 → ignored (on both the sender and the receiver);
- 10 fast taps → 1 note sent;
- old multi polls still count.

**Phone test 207-13:** vote Office, change to Home within 3 min (works). After 3 min it's locked, and both phones show the same.

---

## Phase 207-L: search (both)

### Code check
- **Chats tab** (`home_screen.dart` `_chatsTab()`): **no search** at all.
- **Inside a 1:1 chat:** the ⋮ menu has "Search messages" (`chat_screen.dart` `_startSearch`, ~line 676). It **hides** every message that doesn't match (~line 880): no "3 of 7", no up/down, no jump.
- **Groups** (`group_chat_screen.dart` `_searchBar`, ~line 1192): the good one, with `_matches`, `_goMatch`, "3 of 7", arrows and a jump with a flash.

### L1, search on the Chats tab
- A 🔍 icon on the Chats top bar. Tapping it opens a search box (the tab title moves away; back closes it).
- **Results in 3 parts:**
  1. **Chats**: people and groups whose name matches (avatar + name + last message);
  2. **Messages**: messages that contain the word (name, a short line with the word **bold**, the date). Tapping one opens that chat **at that message** with the 2 s flash (like reply jumps);
  3. "No results for 'xyz'".
- Messages are searched on the phone (1:1 `messages` + `group_messages`, newest first, up to 50, as you type with a 250 ms pause). Hidden/system notes, reactions, votes and deleted messages are left out.
- **Files:**
  - `home_screen.dart` (Chats top bar + search view);
  - new `lib/features/home/presentation/widgets/chats_search.dart`;
  - `local_store.dart` (`searchMessages(q, limit)`, read only);
  - `chat_screen.dart` / `group_chat_screen.dart` (open at a message id).

### L2, inside the 1:1 chat, the same as groups
- Replace the hiding filter with the group style: all messages stay; matches are highlighted; "3 of 7"; ↑ older / ↓ newer; jump + flash.
- Move the group search bar into a shared widget (`chat_search_bar.dart`) used by both.
- **Files:** `chat_screen.dart`, `group_chat_screen.dart`, new `lib/core/widgets/chat_search_bar.dart`.

### Tests
- the Chats search finds a person, a group and a message, and a tap opens at that message;
- in the 1:1 search nothing is hidden, and "2 of 3" moves with the arrows.

**Phone tests:**
- **207-14:** on the Chats tab, 🔍, type "office". You see the group and the messages, and a tap jumps to the message.
- **207-15:** in a 1:1 chat, ⋮ → Search messages, type a word, use the arrows.

---

## Phase 207-M: redo the screens that look basic or faulty (MOCK FIRST)

### What is wrong now (from your screenshots + code)
| Screen | Problem | Code |
|---|---|---|
| **New group · Add people** | "Add people · 1 of 32" reads like page 1 of 32; the big empty page with one friend card looks unfinished; the selected avatar on top is very big | `new_group_screen.dart` |
| **New group · Name and photo** | the **"0/80" sits above the line and "Group name" sits under it** (label in the wrong place, looks broken); the grey check button doesn't say why it's off | `new_group_screen.dart` ~500–535 (`suffixText` + a separate `Text('Group name')`) |
| **"Adding sumaira…" banner** | fixed light colours (`#EEF2FF`) that look wrong in dark mode; the text says Waiting even when Nearby | `group_nearby_widgets.dart` `GroupAddingBanner` |
| **Adding people sheet** | long, hard-to-read text block; the clock icon looks like an error | `showAddingPeopleSheet` |
| **🔒 sealed note** | **stays white in dark mode** (`#F1F1F6` fixed) | `group_nearby_widgets.dart` ~270 |
| **Poll card** | in dark mode the **vote faces are cut on the right** (box 18 px wide, face 18 px + 3 px border); the **count "1" is almost invisible** (fixed `#44454C`); the bar track is bright grey (`#DDDEE6`) in dark; "Poll · select one or more" is very faint; fixed width 250 | `group_extras_widgets.dart` ~400–520 |
| **Votes sheet** | "You … You · 12:32 AM" said twice; plain list | same file |
| **Media viewer** | the video as a small card (207-I); the top bar has no actions (no forward, save or share); the strip at the bottom is small | `media_gallery_viewer.dart` |

### M1, PNG mock (light + dark), for your OK
1. Add people: search on top; selected people as small chips; rows with a tick; "1 selected" in the title; arrow button.
2. Name and photo: one clean name field with the label **inside** ("Group name") and the counter on the right; a short note "Type a name to continue" under the disabled button.
3. In chat: a new "Adding sumaira… · Nearby now" strip (dark-mode colours) + the redone sheet (short lines: Added ✓ / Adding… / Waiting).
4. The sealed note in dark mode.
5. Poll card (one answer): radio circles, full faces, clear counts, the "change for 2:41" line, "Your vote is final".
6. Votes sheet: option headers with counts, people with picture + name + time.
7. Media viewer: full-screen video with controls, a top bar with ↩ Forward / ⬇ Save / ⋮, a bigger strip at the bottom.

**→ Mock done (2026-11-05):** `mock_207_page1.png` … `mock_207_page6.png` (HTML source in `mock207/`). 18 screens:
- p1: Add people, Name and photo (empty, and typed in dark);
- p2: the chat while adding (Nearby strip, 2-line message), the Adding people sheet, the dark chat;
- p3: New poll, the poll after my vote (countdown), the poll after 3 min (dark, other person);
- p4: the Votes sheet, the full-screen viewer video with controls, own video "Preparing… 45%";
- p5: the Chats tab search (light and dark), the search inside a 1:1 chat;
- p6: Private lock Option B on Profile and the Settings card (light and dark).

**Waiting for your OK; no code before it.**

### M2, code exactly like the approved mock
- Theme colours instead of fixed colours (works in light and dark).
- Fix the face clipping (box width = faces × size + border).
- Keep all keys and tests working.
- **Files:**
  - `new_group_screen.dart`;
  - `group_nearby_widgets.dart`;
  - `group_extras_widgets.dart`;
  - `media_gallery_viewer.dart`;
  - their tests.

**Phone test 207-16:** each screen matches the mock in light and dark mode.

---

## Phase 207-N: other things found in the logs

| # | Log | Why (code) | Fix |
|---|---|---|---|
| N1 | Realme 01:19:28 `uncaught_async_error SocketException: Send failed (Network is unreachable)`, from `DiscoveryService.discover` line 45, called by `prepareForAuthentication` | the send is in try/catch, but the error also comes **through the socket stream**, and `socket.listen(...)` has no `onError` | add `onError` (+ `cancelOnError`) to the listen, and return "nothing found" quietly |
| N2 | `THUMB_FAILED PlatformException(MEDIA_STORAGE_FAILED, invalid file)` for a group jpg | `media_storage_service._makeThumb` got a file that was still being written or locked (same race as 207-G) | make the thumbnail only after the file is ready (after G1), retry once after 2 s, then show the grey box quietly |
| N3 | `FILE_SEND_PARTS_FAILED` during the 5-video send | file locked under the send | fixed by 207-G3 |
| N4 | `MEDIA_DECRYPT_SLOW` 14–21 s before a video can play | the whole 20–36 MB file is decrypted before playing | after 207-G: show progress "Preparing 45%" instead of a blank wait (a deeper fix is a later bundle) |
| – | `mali_gralloc`, `IMGSRV`, `MediaCodec`, `IntelliTextProvider`, `libc` | phone system messages | none |
| – | `MESSAGE_SYNC_SKIPPED_NO_TOKEN`, `KNOWN_PEERS_REFRESH_SKIPPED` | not signed in online (phone-only) | none |

**Files:**
- `lib/features/connectivity/data/services/discovery_service.dart`;
- `lib/features/storage/data/media_storage_service.dart`;
- the viewer preparing text.

---

## Phase 207-O: Private profile lock on my picture looks bad (MOCK FIRST)

### What's wrong now (code: `lib/core/widgets/account_avatar.dart` `_lockedCircle`, bundle 203 5b)
- A thick gradient ring, plus a **white gap fixed to `Colors.white`** (stays white in dark mode), plus a white lock bubble with a shadow stuck on the **top-right**, half over the ring.
- It looks pasted on and heavy, worst on small avatars (Settings card r=28, letter avatars).
- It is used only for MY picture while my profile is Private (Profile + Settings card). Friends never see it.

### Mock
`mock_207_lock.png` shows NOW vs Option A / B / C, each in light + dark, at Profile size, Settings card size and as letter avatars.
- **A (my advice):** no ring. A small blue lock badge at the bottom-right, cut out with the page colour.
- **B:** a thin blue ring (no white gap) + the same badge.
- **C:** nothing on the picture; a small "🔒 Private" label under or next to the name.

### Your choice: **Option B** (thin blue ring + small lock badge at the bottom-right)

### Fix (after "go ahead")
1. Change `_lockedCircle` to Option B:
   - a thin blue ring (about 6% of the size, at least 2 px) with a small gap and **no white fill**;
   - a blue lock badge (about 50% of the size, at least 18 px) at the **bottom-right**, cut out with the page colour.
   - The cut-out and the gap use the page colour from the theme, so there's no fixed white in dark mode.
2. Keep the same outside size (no layout jumps).
3. Keep the key `avatar_private_lock` for the tests.
- **Files:**
  - `account_avatar.dart`;
  - the 203 avatar tests.

**Phone test 207-17:** turn on Private profile and check Profile and Settings in light and dark mode. The mark looks like Option B (thin ring + bottom-right badge).

---

## Phase 207-D (updated): finish and deliver
1. Full test suite (old 1555 + the new tests of F–N).
2. `flutter analyze` diff against 206 (no new issues).
3. Kotlin compile check (`ChatVideoPip.kt`).
4. Update `APPLY_207.md`, then the zip `locallink_app_207_<date>.zip`.
5. Commit line + PowerShell steps.
- **Planned commit line:** `v3 3.0.48+119 bundle 207: no gray press, video closes at end, tap reaction +1, fast group add, own media opens, profile picture everywhere, full-screen viewer video, Enter = new line, one-answer polls (3 min change), chats + 1:1 search, redone group/poll/viewer screens, log fixes`

## Phase 207-E (updated): phone tests (you, both phones on 207)
| # | Test |
|---|---|
| 207-1..7 | (as above: no gray, video closes, reactions) |
| 207-8 | new group with a Nearby friend: in within ~10 s, ✓✓ on the first message |
| 207-9 | 5 big videos to a group: all open, no "Not downloaded yet", no freeze |
| 207-10 | change picture: Settings at once; friend within ~30 s |
| 207-11 | viewer: video full screen, plays, pauses on swipe |
| 207-12 | Enter = new line |
| 207-13 | poll: one answer; change within 3 min; locked after |
| 207-14 | Chats tab search: finds a person, group and message; jumps to the message |
| 207-15 | 1:1 search: "2 of 3" + arrows, nothing hidden |
| 207-16 | screens look like the mock (light + dark) |
| 207-17 | Private profile lock looks like Option B (thin ring + bottom-right badge) (light + dark) |

Logs after testing: 5 taps on "Chats" on both phones.
