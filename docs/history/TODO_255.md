# TODO 255 - 10 Nov screenshots + logs (server clock, UI fixes)

Status: **PLAN ONLY - freeze ON.** Nothing is built. It waits for "go ahead 255".
Base: pushed app `0561b07` (3.0.73+144). Backend `2416f0e`: no backend change needed (see A4).
Mock: `mocks/mock_255_ui_fixes.jpg`. Each block shows your screenshot (NOW) and the real widgets rendered with the fix (AFTER).
Planned version: 3.0.74+145. Delivery: ONE app zip, ONE commit, starting with `v3`.

Legend:
- **CONFIRMED** = seen in the logs AND in the code.
- **LIKELY** = the code explains it, but it is not proven.
- **NEEDS YOU** = needs logs, a screenshot or a decision.

---

## A. Server PC clock is ~15 h slow (P1, CONFIRMED)

**What you saw:** messages sent today at 12:40-12:48 show under "9/11/2026" at 9:57-10:04 PM, above "Today".

**Proof:**
- C71 logged `MESSAGE_CLOCK_CLAMPED drift=53014s` at 12:40; Note logged `drift=56615s` at 12:45. That is 14.7 h and 15.7 h.
- The two readings differ by exactly 1 h, 5 minutes apart. The PC clock jumped and is not stable.
- 12:40:27 minus 14.7 h = 9 Nov 9:57 PM, the time shown on the first "hello".

**Code:**
- `lib/core/services/websocket_service.dart:329` - `serverClockOffset` is taken from the server's `ready` frame, with no sanity limit.
- `lib/features/messaging/data/services/reliable_messaging_service.dart:3431` - `_rfc3339Utc()` cuts every message time to "server now" when the phone is more than 8 min ahead of the server.
- It is used at:
  - **:1550 Wi-Fi / Wi-Fi Direct / mesh send (`direct_message`)** - the server is not involved here, so it should never be clamped.
  - :1700 and :3172 - server sends (`send_message`).
  - :2043 - outbox heal after a server `created_at` error.
- Backend `internal/httpapi/api.go:68` `maxFutureMessageSkew = 10 min`: the server refuses messages more than 10 min ahead of ITS clock. That is why server sends need the clamp.

### A1. You (no code)
- [x] On the server PC:
  1. Open Settings > Time & language > Date & time.
  2. Turn on "Set time automatically".
  3. Pick time zone "(UTC+05:00) Islamabad, Karachi".
  4. Press "Sync now".
- [x] If the time goes wrong again after a restart, the PC's clock battery (CMOS) is probably weak.
- [x] Messages already saved keep their wrong time. There is no repair: changing old times could re-order chats.

### A2. App: Wi-Fi / Wi-Fi Direct / mesh messages keep the phone's real time
- [x] At `:1550`, use a new `_rfc3339UtcPhone()`: parse + UTC + `Z`, NO server clamp.
- [x] The receiver already guards against bad phone clocks:
  - native `peer_clock_offset_ms` (line ~2919);
  - "never later than arrival + 5 s".
  So a fast phone still sorts correctly.
- [x] `:1700`, `:3172` and `:2043` (server sends) keep the clamp, because the server's 10-min gate would refuse them otherwise.
  - Side effect while the server clock is wrong: messages that went through the server still get the server's (wrong) time. A3 tells the admin to fix it.
- [x] Log `MESSAGE_TIME_KEPT way=direct` once per app start (not per message).

### A3. App: warn the admin when the server clock is wrong
- [x] In `websocket_service.dart` `ready`, if `|serverClockOffset| > 1 h`:
  - log `SERVER_CLOCK_WRONG offset_s=<n> dir=slow|fast` once per connection;
  - set a `ValueNotifier<Duration?> serverClockWrong255`.
- [x] Admin pages (only while signed in as admin) show a pinned warning bar, using `AdminPage216.pinned`:
  - "Server PC clock is 15 h slow"
  - "Messages and calls get wrong times. On the server PC: Settings > Time > Set time automatically > Sync now."
  - Hours are rounded; "fast" is used when the clock is ahead.
  - (mock block 5)
- [x] Normal users see nothing (no new screens for them).
- [x] The bar goes away by itself on the next `ready` with an offset under 1 h.

### A4. Backend: nothing
- The server cannot know its clock is wrong without internet.
- The app warning (A3) is enough. No backend zip.

**Tests (new `test/bundle255_clock_test.dart`):**
- direct send with offset -15 h keeps the phone time;
- server send with offset -15 h is still clamped;
- banner shows for an offset over 1 h and hides at 59 min;
- `SERVER_CLOCK_WRONG` is logged once per connection.

---

## B. Screen (UI) fixes

### B1. Crown cut at the top of the first row (CONFIRMED in code)
**Seen:** People (3.0.73), Chats list, Calls (first row), admin Network & mesh, admin Calls.

**Cause:**
- `lib/core/widgets/messenger_list_group.dart:92`: the card uses `clipBehavior: Clip.antiAlias` (kept for the tap ripple).
- The crown needs `AdminCrown.room(24)` = 26 dp above the photo. A 2-line `ListTile` leaves only ~12 dp, so ~14 dp is cut.
- Rows 2+ look fine because their crown draws over the row above.
- The Bundle 222 fix (`AdminCrownRoom`) was only added to Profile, Account, Settings and admin Users.

**Fix (same idea as 222, only while the crown shows; others see no change):**
- [x] `MessengerListGroup` gets optional `crownFirstId` + `crownRadius` (+ `crownAlready`).
  - When set, row 0 is wrapped in `AdminCrownRoom(id, radius, already)`.
  - The card keeps its clip, so the ripple stays correct.
- [x] Pass the first row's id in:
  - `contacts_screen.dart` `_contactGroup`: radius 24; also the Requests group.
  - Chats list `home_screen.dart`: each card's first `MessengerConversationTile`, radius 24.
  - `calls_screen.dart` `_groupedList`: first row of each day card, `CallHistoryTile` radius 21.
- [x] Admin `admin_network_screen.dart:97` (row height 62) and `admin_calls_screen.dart:80` (height 64): use the Users-page pattern (`admin_users_screen.dart:33` `_crownExtra222`). An admin row is taller and its photo sits lower.
- [x] The `already` values are measured in tests, not guessed. Test like `crown_room_222_test.dart`: crown top >= card top for People, Chats, Calls, admin Network and admin Calls; a non-admin row keeps its old height.
- [x] Mock block 1 (and the crowns in block 3).

### B2. Crown cut in the chat header (CONFIRMED in code)
- `chat_screen.dart:1034` AppBar (56 dp) clips its title. The photo is radius 20 with 8 dp above it, but the crown needs 22.
- [x] When `AdminCrown.showFor(device.id)`:
  - set `toolbarHeight: kToolbarHeight + AdminCrownRoom.extraFor(20, already: 8)`;
  - wrap the photo in `AdminCrownRoom(radius: 20, already: 8)`.
- [x] Check the second header at `chat_screen.dart:655/820` (radius 23) the same way.
- [x] Non-admin chats keep 56 dp. Mock block 2 (top).

### B3. Chat date chip "9/11/2026" reads like 11 September (CONFIRMED)
- `chat_screen.dart:1427` `_DateDivider` and `core/widgets/messenger_date_divider.dart` (groups) both show `day/month/year`.
- [x] One shared function, `chatDayLabel255(date, now)`:
  - `Today`
  - `Yesterday`
  - within the last 6 days: `Mon 2 Nov`
  - this year: `9 Nov`
  - another year: `9 Nov 2025`
- [x] Use it in both widgets (same pill look).
- [x] Old test that changes: `test/group_design_test.dart:56` expects `'5/1/2026'`; it becomes `'5 Jan'`. Tell you, as usual.
- [x] Mock block 2.

### B4. Calls: the round button covers the last row (CONFIRMED)
- `calls_screen.dart:254`: `padding: EdgeInsets.only(bottom: 28)`. Chats uses 96 (`home_screen.dart:1358`).
- [x] Calls -> 96. People (`contacts_screen.dart:222`, 24) -> 96, because it has the same button.
- [x] Test: scrolled to the end, the last row's call button does not overlap the FAB rect.
- [x] Mock block 3.

### B5. Back-to-back missed calls = one row "Sajjad (3)" (APPROVED by you 2026-11-10; reverses Bundle 174; old tests changed: `calls_group_171_test.dart:66`, missed part of `bundle174_test.dart`)
- Today `call_history_groups.dart:57-58` (Bundle 174, decided before): "a missed call is ALWAYS its own row".
- [x] Only if you say yes: missed calls from the same person, back to back on the same day, join into ONE red row "Sajjad (3)".
  - Answered and outgoing calls never join missed ones.
  - Tap opens the existing list sheet (Bundle 171).
- [x] Old tests that change if yes: `calls_group_171_test.dart:66` "missed calls get their own row" and `bundle174_test.dart` (missed part).
- [x] Mock block 3 shows it.

### B6. Admin chat copy: "Someone" (LIKELY)
- Answer side `app_dependencies.dart:768` `_name221`: for its own messages it uses `store.username`. That is empty for an offline-pending account (noshad was one on 9 Nov).
- [x] Own name order: profile display name -> `store.username` -> `offlinePending['username']`.
- [x] Viewer `admin_chat_viewer_screen.dart:377`: if `sender_name` is empty, use the name from the request label ("noshad & sajjad"): the answering phone's side = first name, the other = second. "Someone" only if both are empty.
- [x] This also helps answers from OLD apps (viewer-side fallback).
- [x] Mock block 4.

### B7. Admin chat subtitle shows the phone name ("from My LinkUp phone'…") (CONFIRMED in code)
- `chat_answer_reader.dart:310`: `fromName = nameOf(device)` -> `peerDisplayName`. With no good profile this gives the phone's label. `My LinkUp phone` is the offline default from `local_store.dart:2620`.
- [x] If the result is empty or a default phone label (`My LinkUp phone`, `My Android Phone…`), use the label name instead.
- [x] Subtitle: "Full chat · from noshad's phone".
- [x] Mock block 4.

### B8. Admin chat header: two letter circles (small)
- `ChatAvatars221` draws letters only.
- [x] Use `AdminPersonAvatar216` (photo when this phone has it: `PeerPhotoBook` by device id) for the answering phone and the other person. Letters stay as the fallback.
- [x] Mock block 4.

### B9. Admin Network & mesh: tiles and rows disagree; default phone names (CONFIRMED in code)
- Tiles count each link flag. Each row shows only ONE tag (`deviceLink216`, `admin_people216.dart:82`).
- That function also guesses **"Server" for any online phone with no flags** (`:97-98`). This is probably why noshad's phone said "Server" while it was not on the server yet (LIKELY).
- [x] Rows show ALL their links as small tags (Server / Wi-Fi Direct / Mesh / Wi-Fi), from the same flags as the tiles. No flags = grey "Online".
- [x] Title: if the phone name is a default label, show "<owner>'s phone". Same helper on the Devices page.
- [x] Subtitle: owner name (+ "through <name>" for a mesh edge, as today).
- [x] Crown room: see B1.
- [x] Old tests: grep `test/` for `deviceLink216` text expectations before changing (Server fallback).
- [x] Mock block 5.

---

## C. Old chat gone on BOTH phones after the update (P0 - checked 2026-11-10, you said no Clear storage)

**Seen:**
- At 11:47 (old app) noshad's chat list had "hi" from yesterday; the admin copy shows 6 messages from 9 Nov.
- At 12:48 (3.0.73) his chat starts at "hello 9:57 PM".
- The 9 Nov chat went by Wi-Fi Direct, so it lived only on the phones. The server never had it.

**What the logs prove (both phones):**
1. The phone's own permissions were OFF when the app opened (`NEARBY_RADIO_READY perm=false`, `BLE_STATE no_permission`, `KEEP_ALIVE notifications=n`), then the app asked for mic / nearby / notifications again.
   - A normal open (for example 7 Nov, every log) shows `notifications=y` and no permission questions.
   - Only Android can turn permissions off. The app has no way to do it.
2. LinkUp's own log files were empty. The logs start at the moment the app opened (C71 12:39:39, Note 12:44:30), but the window is 11:53-12:53.
   - A normal log fills the whole hour (7 Nov 04:56, 11:25).
   - The old app was running until 12:38 ("was=service"), so its lines should be there. The folder (`filesDir/`) was emptied.
3. It was NOT an uninstall:
   - The battery setting stayed "unrestricted / exempted" (an uninstall resets it to "optimized", as on 6 and 9 Nov).
   - The phone still remembered the app's old exits (`app_updated`, `force_stop`). An uninstall forgets them.
4. Right before the open: C71 `force_stop code=10` 7 s before (98 s after the update); Note `force_stop code=10` 198 s before.
   - Code 10 = "user request": the Force stop button, swipe-kill on Realme, or **Clear storage** (it stops the app first).
5. After that: `linkup_mb=0`, `WD_FRIEND_MEMO known=0`, sign in again (`PAIR_PROOF` + `KDF`), C71 history 0 / Note 1.

**What the code shows (clone `0561b07`, 3.0.73):**
- Nothing in the app (Dart or Kotlin) clears app data. No `clearApplicationUserData`, no delete of the database or the log folder. `clearAll` is test-only.
- Changes from 3.0.71 to 3.0.73 under `android/`: only the 246 key warning in `build.gradle` plus notification, service and QR code. No manifest change, no change to how the data is stored.
- Even if the database had broken, that would NOT turn Android permissions off or empty the log folder.

**Result:** permissions off + every file gone + battery setting and old exits kept = the same thing Android's
"App info > Storage > Clear data/Clear storage" does. Something did that on both phones at about 12:38-12:41.
NOT VERIFIED who did it. Possible causes:
- (a) "Clear storage/Clear data" pressed (for example while fixing an install error);
- (b) a cleaner / Phone Manager "deep clean";
- (c) a PC tool or installer that runs a clear (for example `adb shell pm clear`, or some APK installers);
- (d) 3.0.73 itself, which I can't find in code and which can't turn permissions off.

- [ ] **You:** answer the 4 questions in the reply (how installed, sign-in screen, any error, cleaner app).
- [x] If the cause is outside the app: no app code. Next time install over the old app only, then open it.
- [x] Safety, my advice, later and only if you say so:
  - (C1) a "Back up chats" file (Wi-Fi Direct chats exist only on the phones);
  - (C2) on open, log `DATA_FRESH_START` with the reasons, so the next time is clear at once.
- [x] Test (you): on ONE phone, install the next APK over the old one, open it, and send the logs. Chats must stay; there must be no permission questions.

---

## D. Other points from the logs

- [x] **D1. Live connection stays on plain `ws://` after HTTPS turns on (CONFIRMED).**
  - C71: one `WS_OPEN_START ws://…:8080/ws` at 12:40:06, `TLS_243 result=on` at 12:40:23, no reconnect in the next 13 min. Note is the same (12:45:06, 9 min).
  - Fix: when `TLS_243 result=on` and the live socket is `ws://`, reconnect once to `wss://` while no call is active (else after the call). Log `WS_TLS_SWITCH`.
- [x] **D2. Link key still legacy** (`LINK_AUTH legacy reason=no_local_key`, verified=0). Phase 5, unchanged. NEEDS YOU: a 1 h log with both phones together.
- [x] **D3. 3 missed calls before the one that worked (11:44-11:45, old app).** No logs. NEEDS YOU: did noshad's phone ring? Please make a test call on 3.0.73 and send both logs.
- [x] **D4. Admin chat copy: route tag ("Wi-Fi Direct") only on received messages.** Sent messages do not store their route. Small; no change planned.
- [x] **D5.** `ADMIN_ACT_NOT_MINE` replays and `DIRECTORY_REPLY_NO_ROUTE` are known quiet noise. No change.

---

## E. Order, tests, delivery (when you say go)

1. A2 + A3 (clock)
2. B1 + B2 (crown)
3. B3 (dates)
4. B4 (padding)
5. B6 + B7 + B8 (admin chat)
6. B9 (network)
7. D1 (wss switch)
8. B5 (approved)

- New tests: `bundle255_clock_test.dart`, `bundle255_ui_test.dart` (crown rects, FAB gap, date labels, names, network tags), `bundle255_ws_test.dart`.
- Full app suite before the zip. Old tests changed only where listed (B3, B5, B9), and I will tell you.
- Phone checks after install:
  1. Admin pages show the clock bar while the PC clock is wrong, and it goes away after Sync now.
  2. A Wi-Fi message shows the phone's real time.
  3. No crown is cut on People, Chats, Calls, the chat header, admin Network or admin Calls.
  4. The chat shows Yesterday / 9 Nov.
  5. The last call row is above the round button.
  6. The admin chat copy shows names and "from noshad's phone".
  7. Network rows show all links.
  8. The log shows `WS_TLS_SWITCH` and then `WS_OPEN_START wss://`.
