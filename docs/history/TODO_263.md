# TODO 263 - remove the messages a normal user does not need; their work runs by itself (3.0.80+151)

Status: BUILT as 3.0.80+151 (12 Nov, after "Build"). See APPLY_app_3.0.80.md.
Base: app `9d223ef` (3.0.79+150, pushed + verified 12 Nov). Backend: no change.

## Your words
- "Don't show these types of pop-ups that are irrelevant to the user. Check in full app, remove all messages and pop-ups that are not relevant to the normal user." (screenshot: "Waiting for the server ... Sent 22 h ago - carried by 2 phones")
- "Do all the work in auto in background that you removed pop ups."
- Your answers (checkboxes):
  - Q1: remove all the server cards. Keep only the "name was taken" note.
  - Q2: remove all the small server messages.
  - Q3: the security code note goes inside the chat, like WhatsApp.
  - Q4: keep the cards that need an action, as they are.

## Rules for the whole build
1. Only the SHOWING goes. Every job behind a removed card or button keeps running by itself (phase F). No service, timer, retry or log is removed.
2. Widget classes stay where old tests use them (`JoinCard218.done/stuck/carried222`, `AddStatusLine256`, `addStatusText256`, HomeBloc `syncNotice`). Home, Add friend and Account simply stop placing them.
3. Private helpers that are no longer used are deleted (no analyzer warnings).
4. Each hidden card writes one log line so the phone log still tells us what happened (F7).
5. "If anything is working don't touch it": no change to messaging, calls, Wi-Fi Direct, mesh, server, sign-in, or the Kotlin code.

---

## Full app check: what was found and what happens to it

| # | Where | Text the user sees today | Shows by itself? | Decision |
|---|---|---|---|---|
| 1 | Chats tab | "Waiting for the server - Your account was sent with a nearby phone (X)... Sent 22 h ago - carried by 2 phones" | yes | REMOVE (A1) |
| 2 | Chats tab | "Account saved - it will publish itself automatically the moment the server answers. [Publish] [x]" | yes | REMOVE (A2) |
| 3 | Chats tab | "Waiting for the server - Waiting for the server to be updated. [Try again]" | yes | REMOVE (A3) |
| 4 | Chats tab | "You're on the server now - Your account is on the server now / This phone joined your account @x. [Account] [OK]" | yes | REMOVE, except the renamed note (A4) |
| 5 | Chats tab | "@old was taken, so you are @new" / "You are @new on the server now" | yes | KEEP (Q1) |
| 6 | Chats tab (pull down) | "Couldn't sync right now - showing your saved conversations." / "Couldn't reach the server..." / "Couldn't load your conversations..." | after a pull | REMOVE (A5) |
| 7 | Chats tab | snack "Account published to the server." | yes | REMOVE (A6) |
| 8 | Chats tab | "Your new password is only on this phone" | yes | KEEP (Q4) |
| 9 | Chats tab | "Your recovery code changed - save it" | yes | KEEP (Q4) |
| 10 | Chats tab | "Can't join the server yet - linked to @x, ask the admin" / "The server needs a pairing code" | yes | KEEP (Q4) |
| 11 | Chats tab | "Blocked by admin" / "Signed out - Sign in again" / "Update needed" / "Allow nearby devices" | yes | KEEP (Q4) |
| 12 | Profile save | snack "Saved on this phone; it will sync when available" | after a tap | CHANGE to "Profile saved" (B1) |
| 13 | Private profile switch | snack "Saved; will update when online" | after a tap | CHANGE to the online words (B2) |
| 14 | Account page | "Your account is on this phone only. It goes up to the server by itself when the server is found. [Find server now]" + its 3 snacks | yes | REMOVE (B3) |
| 15 | Account page | "Can't reach LinkUp. Showing saved profile." | yes | REMOVE (B4, my advice) |
| 16 | Add friend | "Server connected" / "No server - searching nearby phones" / "Wi-Fi off - using Wi-Fi Direct" + "Find server now" | yes | REMOVE (B5) |
| 17 | Add friend sheet | "device ...a1b2" + Copy device id + snack "Device id copied" | yes | REMOVE (B6) |
| 18 | Sign-up | dialog "Saved on this phone - No LinkUp server answered on this Wi-Fi..." | yes | REMOVE (B7, my advice) |
| 19 | Sign-up / sign-in button | "Looking for the LinkUp server... Asking this Wi-Fi and nearby LinkUp phones (up to 5 s)" / "Server found - Creating your account on the server..." | while spinning | CHANGE to "Creating your account..." / "Signing you in..." (B8, my advice) |
| 20 | First sign-in | snack "Could not check your account history on the server (error). You can restore it later from Account > Account data." | yes | REMOVE, log only (B9, my advice) |
| 21 | Chat | bar on top "X's security code changed. [Check]" / grey line for 24 h | yes | MOVE into the chat like WhatsApp (C) |
| 22 | Chat | "-- Wi-Fi Direct --" / "-- Online --" / "-- Mesh --" where the way changes | yes | NOT TOUCHED (approved in 132; tell me if you want it gone) |
| 23 | Chat photo badge | sheet "Connected by Mesh - your messages hop through..." | only on tap | NOT TOUCHED |
| 24 | Anywhere | errors after something YOU tapped (send failed, photo too big, call no longer available, wrong password) | after a tap | NOT TOUCHED (they are relevant) |
| 25 | Notifications | messages, calls, friend requests, "LinkUp is running" | - | NOT TOUCHED (Android needs the last one) |
| 26 | Admin pages / test switches | admin only | - | NOT TOUCHED |

Checked and not reachable by a normal user: `network_details_screen.dart` (Mesh peers / queued packets, opened from nowhere), `NearbyTestSwitches` and `StorageTestButton` (admin panel only).

---

## A. Chats tab
File: `lib/features/home/presentation/screens/home_screen.dart`.
The list is `ListView(children: [...])` at ~1392. The cards come from `_joinCards218()` at ~531.

### A1 Remove "Waiting for the server - carried by N phones"
- In `_joinCards218()`, delete the item `if (_join218 == null && _carry222.waiting && _carry222.carriers > 0) JoinCard218.carried222(...)`.
- Keep `_carry222`, `_readCarry222`, `_onCarry222` and the `JoinCarrier222.changes` listener. They only feed the log line now (F7: `card=carried n=<carriers>`), once per start.
- `JoinCard218.carried222` stays in `join_cards218.dart` (unused, public).
- The carrying itself (`join_carrier_222.dart`) does not change.

### A2 Remove "Account saved - Publish"
- Delete the row `else if (widget.store.isOfflinePending && _offlineBannerVisible) _offlineAccountBanner(),`. The stuck card row before it becomes a plain `if (...)` (see A3).
- Delete `_offlineAccountBanner()`, `_offlineBannerVisible`, `_offlineBannerDismissed`, `_kOfflineBannerSnoozeKey`, `_offlineBannerSnoozedUntilMs`, and its part of `_loadBannerSnoozes`.
- Keep `_maybeOfferPublish()`. It is the silent publish on Home start (~374) and needs no UI.
- Keep `_publishBusy`. It is used by `_tickPublish256`.

### A3 Remove "Waiting for the server to be updated"
- The stuck row becomes: `if (widget.store.isOfflinePending && _block218.isNotEmpty && _block218 != OfflineAccountSyncService.waitServerBlock236) JoinCard218.stuck(block: _block218, onTry: _tryAgain218)`.
  - Use the existing constant `waitServerBlock236`. Check its name in `offline_account_sync_service.dart` when building.
  - The test lock `JoinCard218.stuck(block: _block218, onTry: _tryAgain218)` stays in the source.
- The `device` and `pairing` cards still show (Q4: they need the admin or a code).
- Checked: `wait_server` does not stop the automatic tries. `autoPublish` at ~590-592 only skips when `block.isNotEmpty && block != waitServerBlock236`.

### A4 "You're on the server now": only the name note stays
- In `_joinCards218()`, the `JoinCard218.done(...)` item gets one more condition: show only when `_join218!['kind'] == 'renamed'`.
  - That covers "@old was taken, so you are @new" and the 132 path "You are @new on the server now".
- Any other kind (`plain`, `linked`) is never drawn. `_readJoin218` clears it straight away: it calls `_closeJoin218()` when kind != renamed, so the notice key is emptied once and a later rename still shows.
- The `_join218 == null` part of other conditions stays as it is.
- `JoinCard218.doneText` does not change (test 218e locks the words).

### A5 Remove the sync chip
- Delete the row `if (state.syncNotice != null && _syncNoticeVisible) _gatedSyncNotice(state.syncNotice!),`.
- Delete `_gatedSyncNotice`, `_SyncNotice` (class at the end of the file), `_syncNoticeVisible`, `_kSyncNoticeSnoozeKey` and the `sync_notice` snooze parts.
- Delete `_armBannerAutoHide`, `_bannerArmed`, `_bannerTimers` and `_bannerHiddenThisSession` if nothing else uses them (check when building; the dispose loop goes with them).
- HomeBloc still sets `syncNotice` (test `home_bloc_local_fallback_test` unchanged). Home just doesn't show it. Pull-to-refresh still reloads, and the saved chats stay on screen.

### A6 Remove the snack "Account published to the server."
- In `_publishSucceeded` (~695-715), delete the `ScaffoldMessenger...showSnackBar(... 'Account published to the server.')` block.
- `_readJoin218()` stays, so a changed recovery code still shows its card (Q4).

### A7 Kept as they are (Q4)
`pwd_reset_only_here_222`, `JoinCard218.recovery`, stuck `device` / `pairing`, `AdminBlockedBanner`, `SessionDeadBanner262`, `VersionBanner`, `NearbyReadyCard`.

---

## B. Other small server / technical messages

### B1 Profile save snack
- File: `lib/features/account/presentation/screens/profile_screen.dart` ~212.
- `Text(synced ? 'Profile saved' : 'Saved on this phone; it will sync when available')` becomes `const Text('Profile saved')`.
- Nothing else changes. `publishOwnProfile()` and the later offline push keep running.

### B2 Private profile snack
- File: `lib/features/account/presentation/widgets/private_profile_card.dart` ~159.
- Drop the `!synced ? 'Saved; will update when online' :` branch, so it always shows `makePrivate ? 'Your profile is private' : 'Your profile is public again'`.
- The `PRIVATE_PROFILE ... synced=n` log stays.

### B3 Account page "on this phone only + Find server now"
- File: `lib/features/account/presentation/screens/account_center_screen.dart`.
- At ~323, delete the `if (widget.store.isOfflinePending) ...[ SizedBox, _phoneOnly256(context) ]` branch.
- Delete `_phoneOnly256` (~156-190), `_findServer256` (~192-208), `_finding256`, and the 3 snack texts.
- The chain becomes `if (!widget.store.isOfflinePending && error != null) ...[ ... ]`, so a phone-only account sees no box and no error.
- In `initState` (~95), add `OfflinePublishTicker256.instance.nudge('account_open');` (F1).

### B4 Account page "Can't reach LinkUp. Showing saved profile."
- Same file, ~331-350: delete the `if (showOfflineBox) _note(key: ValueKey('account_offline_box') ...)` branch. The saved profile simply shows.
- Keep the `else` red `LocalLinkInlineError` ("Your saved profile is shown. <error>" + Retry). It shows only for a real failure while the server IS connected.
- Keep `_serverSub`, which reloads when back online. Remove `showOfflineBox` if it is no longer used.
- Old test change: `test/bundle183_test.dart` ~871-873 now expects `findsNothing` for `account_offline_box` (listed in APPLY).

### B5 Add friend status line
- File: `lib/features/directory/presentation/add_contact_screen.dart`.
- At ~280, delete `if (widget.connectivity != null) _status256(),`.
- Delete `_status256`, `_findServer256` and `_finding256` (~446-471).
- In `initState` (~76), add once, after the first frame:
  - `OfflinePublishTicker256.instance.nudge('add_open');`
  - if no phone-only account is waiting: `unawaited(widget.connectivity?.refresh())`. This is the same work the "Find server now" tap did.
- `addStatus256` / `addStatusText256` / `AddStatusLine256` stay in `add_friend_256.dart` (test bundle256 uses them).

### B6 Add friend sheet: device id
- File: `lib/features/directory/presentation/nearby_people_section.dart` ~527-545.
- Delete the `Row` with `Text('device …$tail')`, the Copy `IconButton` and the "Device id copied" snack.
- Delete `final tail` (~483) and the `services.dart` import if Clipboard is no longer used.
- The sheet still shows the photo, "Add <name> as a friend?" and the buttons.

### B7 Sign-up dialog "Saved on this phone"
- File: `lib/features/authentication/presentation/screens/setup_screen.dart`.
- At ~83, delete `if (outcome.madeOffline && mounted) await _savedOnPhone256();`, and delete `_savedOnPhone256` (~108-127).
- The user goes straight into the app. The account goes up by itself (F1).
- The log line `SIGNUP ... offline` stays (check its name when building).

### B8 Sign-up / sign-in spinner words
- Same file, `_stage256` (~129-160):
  - First line: always `_controller.registerMode ? 'Creating your account…' : 'Signing you in…'`.
  - Second line ("Asking this Wi-Fi and nearby LinkUp phones (up to 5 s)" / "...on the server…"): removed.
  - "Server found" + green tick: removed. The spinner stays until it is done.
- Keys `signup_stage_$stage` stay. No test uses these texts (checked).

### B9 First sign-in history snack
- Same file, ~207-212: replace the snack "Could not check your account history on the server (...)" with `AppLogger.warning('RESTORE_MANIFEST', detail: 'fail ${cleanBlocError(error)}')`. The `return` stays.
- Restore is still available later at Account > Account data, and the same check runs again on the next sign-in.

---

## C. Security code changed: in the chat, like WhatsApp
Today (`lib/features/messaging/presentation/screens/chat_screen.dart`):
- `_keyChangeBanner245(context, device), // Bundle 245` at ~1216 puts a bar on top of the chat. It shows a red "X's security code changed. [Check]" while waiting, or a grey line for 24 h (`_autoKeyLine258`) once taken by itself.
- Both disappear: after 24 h, or when the code page is opened (`autoSeen258`).

New:
- **C1 No bar on top.** Remove `_keyChangeBanner245(context, device), // Bundle 245` from the body `Column`.
- **C2 A small centred pill INSIDE the messages**, at the time of the change, in the same style as the date pill (`_DateDivider`: `surfaceContainerHighest`, pill radius, `labelSmall`).
  - It has a 12 px lock icon and the text "Noshad's security code changed. Tap to learn more." (max 2 lines, centred).
  - Tap opens the Security code page (`_openSecurityCode245`).
- **C3 It stays in the chat** (WhatsApp keeps it). In `lib/core/security/security_code_245.dart`, `SecurityCode245` gets an event list:
  - `static const String eventsSettingKey = 'key_events_263';`
  - `class KeyEvent263 { userId, oldDeviceId, deviceId, at, waiting }` with `toJson/fromJson`.
  - The list lives in memory as `_events` and is saved as JSON in settings (no database change).
  - It keeps at most 20 events per person, and events older than 365 days are dropped on save.
  - `load()` reads it next to the 2 old keys. The lock `SecurityCode245.instance.load(read: readSetting, write: writeSetting)` in `local_store.dart` stays as it is.
  - **First load after the update:** if `key_events_263` is empty, events are made from the existing `_auto` (taken, last 24 h) and `_pending` (waiting) entries, so a change from yesterday still shows.
  - `noteCardChange(...)` adds `KeyEvent263(waiting: true)` (the same change again = no new event).
  - `autoTake258(...)` adds or updates an event:
    - if a waiting event for that user exists, it becomes `waiting: false` (one pill, not two);
    - otherwise a new `waiting: false` event is added.
  - New `List<KeyEvent263> eventsFor(String deviceId, {String userId = ''})` matches by user id, or by the old or new phone id (a friend on a new phone = one chat, 237). Sorted by time.
  - Log line: `KEY_EVENT_263|user=..1234 waiting=y|n`.
  - Opening the code page no longer hides anything. `autoSeen258` stays (harmless; it only marks the old auto entry).
- **C4 Waiting change** (no proof yet, rare):
  - The same pill, with the text "Noshad's security code changed. Tap to check." The page has "Accept new code" (as today).
  - The automatic re-check (258 A3 `pendingCards`) is untouched. When proof comes, the event becomes taken and the text changes by itself (notifyListeners).
- Built note: the placement rule lives in `KeyEvent263.between(events, from, upTo)` / `KeyEvent263.after(events, last)` (security_code_245.dart, testable); the chat calls them through `keyEventsBefore263` / `keyEventsAfterLast263`. `accept()` (Accept new code) also turns the waiting note into a taken one.
- **C5 Where the pills go** (no change to message rows, keys or index math):
  - `ChatScreen` state listens to `SecurityCode245.instance` (`addListener` in `initState`, `removeListener` in `dispose`) and calls `setState`.
  - In `build`: `final keyEvents = searchQuery.isEmpty ? SecurityCode245.instance.eventsFor(device.id) : const <KeyEvent263>[];`.
  - In `itemBuilder` (~1251), for message `index`, the pills are the events with `at` after `visibleMessages[index-1].createdAt` (none for index 0) and not after `message.createdAt`. They go in the row's `Column` just before the date divider.
  - Events after the last message go in the LAST row's `Column`, under the bubble.
  - A chat with no messages shows nothing: the empty view stays, like WhatsApp.
- **C6 Widgets and test locks.**
  - `_autoKeyLine258(BuildContext context, Device device, List<KeyEvent263> events)` returns `KeyedSubtree(key: const ValueKey('chat_key_auto_258'), child: Column(children: [pill per event]))`. That gives one keyed group per slot (no duplicate keys) and no Button inside, so the bundle258 lock (~364-369) stays true.
  - The doc comment `/// Bundle 245 (audit S7): "<name>'s security code changed" ...` stays right after `_autoKeyLine258`. Under it, `_keyChangeBanner245` is renamed in place to the waiting-pill builder, and its `InkWell` keeps `ValueKey('chat_key_change_check')`. So bundle258 needs no change.
  - Old test change: `test/bundle245_test.dart` ~192 expects `_keyChangeBanner245(context, device), // Bundle 245` in the body. It changes to expect `_autoKeyLine258(context, device,` inside `itemBuilder` and no `_keyChangeBanner245(context, device), // Bundle 245` (listed in APPLY).
- **C7 Unchanged:**
  - The verify flow, "Accept new code", the call warning for a Verified friend, and `SecurityCodeScreen`.
  - No change to the Chats list preview (WhatsApp doesn't show it there).
  - Group chats: no change (they have no key bar today).

---

## E. The ZTE (@alex) screenshot - CHECKED in the ZTE log of 11 Nov 19:57: NOT an app bug
- The screenshot is from 11 Nov 19:27 (file IMG-20261111-...). At that time NO phone could reach the server:
  - C71 and TECNO: `WS_CLOSED error=TimeoutException` every ~40 s from 18:58 until `WS_READY` at 19:39:01 (TECNO) / 19:39:10 (C71).
  - ZTE: `SERVER_SEARCH none reason=no_answer` and `OFFLINE_ACCOUNT_PROBE fail ... took too long` every 60 s / 5 min from 19:12 to 19:36 (before 19:12: `no_wifi`).
- When the server came back the ZTE joined by itself: 19:40:07 `SERVER_SEARCH found http://192.168.18.27:8080`, 19:42:19 `OFFLINE_ACCOUNT_DONE user=@alex linked`.
- So the card was true at 19:27, but not useful -> removed by A1. "Sent 22 h ago" = the box was made when the account was made on the phone (10 Nov evening).
- Small finding (NOT fixed here, nothing broken): the first try at 19:40:08 came from the background (`from=background`) and kept the lock with no result until ~19:42 (`OFFLINE_ACCOUNT_BUSY` at 19:40:10 and 19:41:09); the next try at 19:42:09 worked. About 2 min lost. Fix only if it shows again.
- The 401 after 19:42:53 is TODO 262 D (admin console clue, signed-out card in 3.0.79).

---

## F. The work behind the removed messages runs by itself

### F1 Phone-only account upload (was: "Publish", "Find server now" x2, the sign-up dialog)
- Already automatic: `OfflinePublishTicker256` tries every 60 s for 10 min, then every 5 min. It also tries on `wifi_up`, `resume`, `server_saved` and `server_hint`, and there is the background publish (236).
- New nudges in place of the removed buttons:
  - Add friend screen opens: `nudge('add_open')` (B5)
  - Account page opens: `nudge('account_open')` (B3)
  - Chats pull-to-refresh: `_refresh()` (~717) adds `OfflinePublishTicker256.instance.nudge('refresh');`
- `nudge` keeps its 5 s gap and its lock (no double run). It does nothing when no phone-only account waits (`_run == null`).

### F2 Carried account (A1)
`JoinCarrier222` keeps making, sending and carrying the box by itself. No change.

### F3 Server not updated yet (A3)
The ticker keeps trying with `wait_server`. No button is needed (checked ~590).

### F4 Profile / private profile saved offline (B1, B2)
Sent by itself when the server or a friend is reached (207 / 236 push). No change.

### F5 Security code waiting (C4)
Checked again by itself (258 A3). No change.

### F6 Chats sync failure (A5)
HomeBloc keeps its own retry (`_startLocalDiscovery` + reload on reconnect). No change.

### F7 Log lines
`UI_HIDDEN_263|card=carried|wait_server|publish|done|sync_notice|account_phone_only|add_status|signup_saved`
- Written once per app start per card, when the old code WOULD have shown it.
- Guarded by a static `Set<String>`, so there is no line per screen frame.
- Done in a tiny helper `lib/core/diagnostics/ui_hidden_263.dart`: `UiHidden263.note(String card, [String detail = ''])` + `resetForTest()`.

---

## T. Tests + version

### New `test/bundle263_test.dart`
- **A (Home, widget tests with the existing Home test harness):**
  - A-1: pending account + carried status (2 carriers) shows no "Waiting for the server" and logs `UI_HIDDEN_263|card=carried`.
  - A-2: pending account, no block: no "Account saved" text and no `offline_publish_button`.
  - A-3: block `wait_server`: no `join236_wait_server`. Block `device`: `join218_stuck_device` still shows.
  - A-4: join notice `plain` / `linked`: no `join218_done`, and the notice key is cleared. `renamed` with was: "@old was taken, so you are @new" shows.
  - A-5: `syncNotice` set: no "Couldn't sync right now" text.
  - A-6: recovery code and pwd-only-here cards still show.
- **B:**
  - B-1: Account page with a pending account: no `account_phone_only_256`, no `account_find_server_256`, and `nudge('account_open')` is called.
  - B-2: Account page with the server down: no `account_offline_box`.
  - B-3: Add contact: no `add_status_256`, and `nudge('add_open')` is called.
  - B-4: nearby Add sheet: no "Copy device id", no "device …".
  - B-5: profile snack source = `'Profile saved'` only. Private card source has no "will update when online".
  - B-6: setup source has no `_savedOnPhone256`, no "Looking for the LinkUp server", and no "Could not check your account history".
- **C:**
  - C-1: `SecurityCode245` events: noteCardChange makes a waiting event, autoTake258 turns it into one taken event (not 2), the cap is 20 per person, and events older than 365 days are dropped.
  - C-2: migration: an old `key_auto_258` + `key_change_245` with no `key_events_263` makes events.
  - C-3: `eventsFor` matches by the old phone id, the new phone id and the user id.
  - C-4 (chat widget): messages at 10:00 / 10:10 with an event at 10:05 put the pill between them. An event at 10:20 puts it under the last bubble. No top bar.
  - C-5: tap opens `SecurityCodeScreen`. Back: the pill is still there.
  - C-6: waiting text "Tap to check" changes to "Tap to learn more" after autoTake258.
  - C-7: in search mode there are no pills.
- **F:**
  - F-1: pull-to-refresh calls `nudge('refresh')` (ticker fake).
  - F-2: `UiHidden263.note` writes once per card.

### Old tests changed (to be listed in APPLY)
- `test/bundle218e_test.dart` ~203: `contains('else if (widget.store.isOfflinePending && _offlineBannerVisible)')` becomes `isNot(contains('_offlineAccountBanner()'))` (the banner is gone, A2).
- `test/bundle245_test.dart` ~192: the top-bar line becomes the in-chat call (C6).
- `test/bundle183_test.dart` ~871-873: `account_offline_box` now `findsNothing` (B4).
- `test/bundle223_logs_test.dart`, `test/nearby_190_test.dart`: version lines 3.0.80+151.

### Version and checks
- Version 3.0.80+151 (`lib/core/config/app_build.dart`, `pubspec.yaml`).
- `flutter analyze`: 0 errors.
- Full Flutter suite in chunks: all pass.
- Kotlin: no change, run once (460).

### Delivery
One app zip `locallink_app_3.0.80_<date>.zip` + one commit `v3 3.0.80+151 bundle 263: ...` + `APPLY_app_3.0.80.md` (PowerShell block) + `docs/history/TODO_263.md`.

---

## Phone checks (after install)
1. A phone with a phone-only account:
   - The Chats tab shows only the chats, with no server card.
   - The log has `UI_HIDDEN_263|card=carried` (or `publish`) and `OFFLINE_ACCOUNT` tries every 60 s / 5 min.
   - Opening Add friend logs a try with `why=add_open`.
2. Add friend: no "Server connected / No server" line, and no device id in the Add sheet.
3. Account page with the server off: no box and no "Find server now". The profile shows.
4. A friend reinstalls (or uses a new phone): in your chat with them, a small pill "X's security code changed. Tap to learn more." sits between the messages. Tapping it opens the code page, and the pill is still there afterwards.
5. Profile save with the server off: the snack says "Profile saved", and friends get the change later by themselves.
6. A new sign-up with no server: no "Saved on this phone" dialog. The button only says "Creating your account..." and then the app opens.
7. Still shown when needed: recovery code changed, signed out - sign in again, blocked, update needed, allow nearby devices.
