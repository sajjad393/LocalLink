# APPLY 207: no gray press, video closes at end, tap reaction +1, fast group add, own media opens, profile picture everywhere, full-screen viewer video, Enter = new line, one-answer polls, search, redone screens, private lock B (app 3.0.48+119)

Base: app `8e7f0ab` (206, 3.0.47+118; push checked: same as the 206 zip).
Plan: `TODO_207.md`. Zip: `locallink_app_207_2026-11-05.zip` (app only, no backend change).

## P1: no gray overlay on the floating buttons
- New `lib/core/widgets/no_gray_press.dart` (`NoGrayPress`):
  - no splash and no gray highlight while you press or hold;
  - the button shrinks to 95 % while your finger is down, then goes back;
  - it doesn't take the tap, the hold-to-move (206) or the tooltip.
- Used by:
  - the round buttons on Chats, Calls and People (`brand_gradient_fab.dart`);
  - the square Next / Create buttons on "New group" (`SquareGradientFab`); the grey "off" button doesn't shrink;
  - the small "Jump to latest" button in a chat.

## P2: the video player closes when the video ends
- `chat_video_hub.dart` watches the playing video. When a video that was **playing** reaches its end:
  - **full player:** closes; you're back in the chat (or the photo viewer), and the bubble shows the preview + play button;
  - **small floating player:** closes at once (it used to wait 5 s with a replay button);
  - **Android floating window (over other apps):** the window closes and the app stays in the background (new `close` in `ChatVideoPip.kt`, `moveTaskToBack`).
- If you pause near the end and drag the bar to the end, nothing closes.
- Log line: `VIDEO_END_CLOSE where=full|mini|pip`.

## P3: tap an emoji under a message
- New `lib/core/widgets/reaction_chips.dart` (shared chips + the add/remove/change rule).
- **1:1 and groups:**
  - Friend reacted ❤️ 1. Tap it and yours is added: ❤️ 2.
  - Tap your own again and it's removed: ❤️ 1.
  - You had 👍 and tap ❤️: yours changes to ❤️ (one reaction per person).
  - Your own emoji has a light blue border.
- **Groups:** "who reacted" now opens when you **hold** the chip (tapping used to open it). In an "admins only" group a member gets the same "can't send" note as before.
- **1:1 remove (new):** sent as the same hidden reaction note with an empty emoji (the way groups already do it). The friend's phone deletes it. An older app ignores it, so update both phones.
- Log line: `REACTION_TAP add|remove|change chat=1to1|group`.
- No database change.

## F: adding people to a group is fast when they are Nearby
- **Seen on the same Wi-Fi = sent now.** On the same Wi-Fi a friend shows up as "discovered" every few seconds, not as "connected", so the waiting "added you" card used to wait 15 s, 30 s, 60 s … up to 15 min. Now the card and messages go out when the friend is seen (at most once every 20 s per friend). Log `GROUP_PEER_SEEN_FLUSH`.
- **Short waits while Nearby:** while the person shows Nearby, the wait between tries is at most 20 s for the card and 60 s for messages (it was up to 15 min). Not Nearby = the old waits.
- **Logs:** every try 1, 2, 3, 5, 10, 20 and every failed try is logged with `next_s` and `near`. A dropped group packet now says why: `GROUP_PACKET_DROPPED why=not_sealed / not_final / bad_json / blocked / bad_card / card_bad_key / card_not_in_it` (once a minute per reason).
- **Banner + "Adding people" sheet (mock 207 page 2):** theme colours (fine in dark mode). The banner says "Nearby now · a few seconds" when the person is near. The sheet shows "1 of 3 added", a spinner with "Adding now · Nearby", a "Waiting" pill, "Couldn't be added" + Try again, and "Done". The sealed chip is a light blue chip with a lock, in light and dark.
- `group_need` on start was dropped from the plan: a phone that has not got the card yet does not know the group, so it can't ask. The sender sending when it sees the person (above) covers it.
- Files: `group_nearby_service.dart`, `group_nearby_widgets.dart`, `app_dependencies.dart`; tests in `groups_g3_test.dart` (+3).

## G: my own photos / videos open (no "Not downloaded yet", fewer freezes)
- **G1, one lock job per file:** the chat tile, the grid and the viewer used to lock (encrypt) the same video at the same time; the first one deleted the plain file under the others (`ATTACHMENT_PREPARE_FAILED … Cannot delete file`). Now a second caller waits for the same job. A plain file that is already gone is no error.
- **G5, one big file at a time:** files are locked one after another, not 5 at once (that froze the screen for 6 s).
- **G2, the locked path is saved:** after locking, every saved attachment row that named the plain file names the `.enc`, so every screen opens the same file. Log `MEDIA_LOCKED_SAVED`.
- **G3, not under a send:** while a plain file is being copied for sending, it is locked but not deleted; it is deleted right after the copy ends.
- **G4, the viewer opens files itself:** a page with no ready view, but whose file is on the phone, shows "Preparing…" and then the photo / video. "Not downloaded yet" only when the file is really not on the phone. Logs `MEDIA_VIEWER_PREPARED`, `MEDIA_VIEWER_PREPARE_FAILED`.
- The 1.7 s `MAIN_STALL … Linux.readBytes` came from the Android side while the app opened; not changed here (check on the phone with 207-9).
- Files: new `lib/core/services/file_in_use.dart`; `file_transfer_service.dart`, `local_store.dart` (`replaceAttachmentLocalPath`, no DB version change), `send_copy_book.dart`, `media_gallery_viewer.dart`, `app_dependencies.dart`; new test `test/bundle207g_test.dart` (6).

## H: my new profile picture shows in Settings and at friends
- **H1, Settings card:** shows your real profile file (like Profile and Account), not the friends' picture book. It reloads at once when you save in Profile (new `OwnProfileSignal`).
- **H2, right away:** saving updates your own picture-book entry even when no signed card can be made yet (phone-only account: keyed by your phone id). Group "You" rows and poll faces change at once.
- **H3, friends get it with retry:** when your picture changes (or you remove it), your signed card goes **straight to each friend**, not only by broadcast. If a friend was not reached, it is sent again when that friend is next seen (gap 60 s, at most 5 times). Logs `PEER_CARD_TO_FRIENDS count=`, `PEER_CARD_SENT`, `PEER_CARD_WAIT`.
- **H4, an old ask gets the new card:** the ZTE asked 9 times with your old picture code and got silence. Now it gets your current card (once a minute), asks again with the new code and gets the picture.
- **H5, every skip is logged:** `PEER_PHOTO_SKIPPED why=old_code / no_file / limit / blocked / not_started / no_account`.
- No wire change: the card and picture messages are the same as in 204.
- Files: new `lib/features/account/data/own_profile_signal.dart`; `messenger_settings_screen.dart`, `profile_screen.dart`, `directory_repository.dart`, `peer_photo_book.dart`; tests `profile_photo_204_test.dart` (+3), new `test/bundle207h_test.dart` (2).

## N: other things from the logs
- **N1:** "Network is unreachable" from the server search came through the socket stream as an uncaught error (Realme 01:19:28). The listen now has `onError` + `cancelOnError`: nothing found, quietly.
- **N2:** a small picture that fails ("invalid file", still being written) is tried once more after 2 s (`THUMB_RETRY`), then the grey box quietly.
- **N3:** the send / lock race is fixed by G3.
- **G5 follow-up:** files up to 2 MB (small pictures, voice notes) are locked at once and do not wait behind a big video.
- **N4** ("Preparing 45%" progress during the long video decrypt) is not done here: the viewer shows "Preparing…" (G4). Real progress needs a later bundle.
- Files: `discovery_service.dart`, `media_storage_service.dart`, `file_transfer_service.dart`; tests in `bundle207g_test.dart` (+2, and the queue test now checks small files too).

## J: keyboard Enter = new line
- 1:1 and group message boxes: the keyboard shows Enter (new line) instead of Send. The box grows up to 5 lines, then scrolls. Send only with the send button. Search boxes and the group name box are unchanged.
- Files: `chat_composer.dart`, `group_composer.dart`; `test/composer_test.dart` (the old "keyboard send" test now checks Enter never sends, +1 test).

## K: polls: one answer, change allowed for 3 minutes (+ poll screens from mock page 3/4)
- **K1:** the "Allow more than one answer" switch is gone. New polls are always "POLL · CHOOSE ONE"; a short note explains the 3-minute rule. Old polls with many answers still work as before (check boxes, no time rule).
- **K2:** tap another option = your vote moves; tap your own = taken back (within the 3 minutes).
- **K3, 3 minutes:** a one-answer vote note now carries `f` = time of your first vote (`llvote:v1:{p,c,at,f}`). Every 207 phone ignores a change more than 3 min after `f` and keeps the earliest `f` it saw, so all phones show the same. Logs `GROUP_VOTE_LATE_IGNORED`, `GROUP_VOTE_FINAL`. Older phones ignore `f`.
- **K4:** under the poll: "You can change your vote for 2:41" (counts down), then "Your vote is final" with a lock. A tap after that shows "Votes can't be changed after 3 minutes".
- **K5:** fast taps: only the last vote is sent, 1.5 s after the last tap (it was one group message per tap). Log `GROUP_VOTE_SENT`.
- **K6 + M (Votes sheet, mock page 4):** each option with "1 vote · 50%" and a bar, people with the time on the right (no "You · You"), "Not voted yet" with the members who did not vote, theme colours (dark mode).
- **M (poll card, mock page 3):** radio circles, full faces (no cut), counts and track readable in dark, "2 of 3 voted · View votes" at the bottom.
- Files: `group_extras.dart`, `group_extras_book.dart`, `group_messaging_service.dart`, `group_extras_widgets.dart`, `group_chat_screen.dart`; tests `groups_g5b_test.dart` (+8, 4 updated).

## Other
- `pubspec.yaml` 3.0.48+119, version stamp, `test/nearby_190_test.dart` scan.
- Tests: new `test/bundle207_test.dart` (14 tests). Updated:
  - `chat_media_147_test` (the mini player closes at once);
  - `group_chat_screen_test` (hold = who reacted, plus a new tap test);
  - `support/chat_video_fakes.dart` (`finish()`, `FakePip.close`).

## Checks done here (no phone)
- Flutter tests: **1605 / 1605 pass** (155 test files, the full suite, run on the final code).
- `flutter analyze`: **166 issues vs 169 on 206, no new ones** (3 old ones went away; the 6 new lint notes were fixed).
- Kotlin (`ChatVideoPip.kt`): kcheck clean (classes = 181). This is a compile check only, so how the floating window closes has to be checked on the phone.
- No DB change and no backend change.
- Not done: N4 (on purpose, see N). "Preparing…" shows no % (the prepare step has no progress report).

## Phone tests
1. **207-1** Hold the Chats, Calls and People buttons, "Jump to latest" and Next on "New group": no gray. The button shrinks a little, and a tap still opens it.
2. **207-2** Play a video full screen to the end: it closes by itself.
3. **207-3** Play it in the small floating player to the end: it closes at once.
4. **207-4** Video playing, press Home (floating window over other apps), let it end: the window closes.
5. **207-5** Pause near the end and drag the bar to the end: it stays open.
6. **207-6** 1:1 chat: friend reacted ❤️. Tap ❤️: ❤️ 2 on both phones. Tap again: ❤️ 1 on both phones.
7. **207-7** Group: tap a chip to add or remove yours; hold a chip to see who reacted.
8. **207-8** New group with a friend who is Nearby: they are in within about 10 s, and the first message gets ✓✓.
9. **207-9** Send 5 big videos to a group: all of them open on your phone, with no "Not downloaded yet" and no freeze.
10. **207-10** Change your profile picture: Settings shows it at once, and a friend sees it within about 30 s.
11. **207-11** Open a video from the chat gallery: it plays full screen by itself. Swipe away and it pauses. Tap it for -10 / +10 and the seek bar. At the end it stays on the last frame with replay.
12. **207-12** Press Enter in the 1:1 and the group message box: you get a new line, not a send.
13. **207-13** Poll: one answer only. You can change it within 3 min (countdown), then it shows "Your vote is final".
14. **207-14** Chats tab, tap 🔍, type "office": you see the group and the messages; tap a message and it jumps there with a flash.
15. **207-15** 1:1 chat, ⋮ → Search messages, type a word: nothing is hidden, "2 of 3" shows, and the arrows jump.
16. **207-16** New group (Add people + Name), the Adding sheet, the poll, Votes and the viewer bars look like the mock in light and dark mode.
17. **207-17** Turn on Private profile: Profile and Settings show a thin blue ring and a small blue lock at the bottom-right (light and dark).

Logs after testing: 5 taps on "Chats" on both phones.

## Commit
`v3 3.0.48+119 bundle 207: no gray press, video closes at end, tap reaction +1, fast group add, own media opens, profile picture everywhere, full-screen viewer video, Enter = new line, one-answer polls (3 min change), chats + 1:1 search, redone group/poll/viewer screens, private lock B, log fixes`

## I - Viewer video full screen (mock page 4, screens 11-12)
- `chat_video_player.dart`: new `page` / `active` params. Page mode fills the screen (black, centred video), plays by itself when the page is shown (`VIEWER_VIDEO_AUTOPLAY`), pauses when swiped away, plays again when swiped back. Tap shows -10 / play-pause / +10, seek bar, time, sound (above the small pictures strip); they hide after 3 s. No full-screen button in page mode. At the end it stays on the last frame with the play button (play = from the start); the viewer stays open. Never goes to the mini player; leaving the viewer stops the video. Normal bubbles unchanged.
- `media_gallery_viewer.dart`: video pages use the page mode with `active: i == current` (old 72 px padded tile removed).
- "Preparing…" stays a spinner without % (the prepare step has no progress report; adding one would change the file repository contract).
- Tests: `test/bundle207_test.dart` +4 (autoplay + no full-screen button, pause on swipe, last frame + replay from 0, no mini on leave); `test/support/chat_video_fakes.dart` Rig.player gets `page`/`active`. 92/92 video + media tests pass.

## L1 + L2 - Search (mock page 5, screens 13-15)
- L1 Chats tab: a search icon on the Chats top bar (`TabTopBar` gets optional `actions`). It opens a search bar (back, rounded box, X clears; Android back closes the search first). Results: filter chips All / Chats / Messages / Media; CHATS (people + groups by name, with last message + time); MESSAGES · N (name, "You: " / "Ali: " + the line with the word in bold on a light blue mark, time); "No results for 'xyz'". Messages are searched 250 ms after typing stops.
- Tap a message: that chat opens AT the message with the 2 s flash (new `jumpToMessageId` on `ChatScreen` and `GroupChatScreen`; the notification `initialMessageId` path is unchanged).
- New `LocalStore.searchMessages(q, limit: 50)` (read only, no DB change): 1:1 `messages` + `group_messages` (joined to groups), body or file name LIKE, newest first. New `lib/core/models/message_search_hit.dart` drops matches only in the hidden wire part, deleted messages, group system notes and locked messages. Polls are found by their question.
- New `lib/features/home/presentation/widgets/chats_search.dart` (`ChatsSearchBar`, `ChatsSearchView`). Logs: `CHATS_SEARCH_OPEN`, `CHATS_SEARCH len= hits=`, `CHATS_SEARCH_OPEN_RESULT`, `CHATS_SEARCH_FAILED`.
- L2 1:1 chat: search no longer hides messages. It uses the shared new `lib/core/widgets/chat_search_bar.dart` (also used by groups; the group keys are kept): "2 of 3", up = older, down = newer, jump + flash; words marked yellow in bubbles (`MessageBubble.highlight`).
- Tests: new `test/bundle207l_test.dart` (15); `groups_g1_test.dart` + `bundle183_test.dart` source scans updated. 412 related tests + 47 pass.

## M2 (rest) + O - Screens like mock pages 1, 2, 4, 6
- New group, Add people (`new_group_screen.dart`): title line "2 selected · up to 32" (was "Add people · 2 of 32"); the search box is always on top (the search button is gone); picked people are small pills (picture + name + x); NEARBY NOW friends first, then YOUR FRIENDS.
- New group, Name and photo: one clean box with the label "Group name" INSIDE and the counter on the right (the old "0/80 above, Group name under the line" is gone); the description is a soft filled box; "N MEMBERS" with You first; "Type a name to continue" next to the grey check button.
- Adding people sheet: "Waiting · not near or online yet" and a short note ("You can write now. They get your messages right after they join."). The strip and the sealed note already use dark-mode colours (from F).
- Media viewer: Forward (when chats can be listed) / Save to phone (received file on this phone) / ⋮ File info in the top bar; bigger strip pictures (52 px); "Preparing…" plus "Your video · 19.4 MB · plays in a moment". The review mode (before sending) keeps only Remove.
- O, the private lock is now Option B (`account_avatar.dart`): a thin blue ring (6 % of the radius, at least 2 px) with no white fill and a see-through gap, and a blue lock badge (at least 18 px) at the bottom-right. The badge's cut-out uses the colour behind it (the card or the page), so there's no fixed white in dark mode. Same outside size; the key `avatar_private_lock` is kept.
- Tests: new `test/bundle207m_test.dart` (7); `groups_g1_test.dart`, `groups_g3_test.dart` and `bundle207g_test.dart` updated. 122 + 121 related tests pass.
