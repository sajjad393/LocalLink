# TODO 313 - Calls line + My links map + Get chats back + Conversations page

Status: BUILT ("Build" 15 Nov) as 3.0.106+177, base app `9ec8f68`. See "As built" at the end.
Source: `Screenshot_20261115-231441.png` (Calls), `Screenshot_20261115-231247.png` (Chats).

## A. Calls: "1 missed" breaks in the middle (issue 2) - FIX
- Seen: ayesha row: "No answer, 9:30 PM · 1" / "missed" on 2 lines.
- Code: `lib/features/calls/presentation/widgets/call_history_tile.dart` ~l.158-170: `Text.rich`
  `'${_statusLine()} · '` + `L.t.missed(n)` ("{missed} missed"), `maxLines: 2` (Bundle 285 wants the
  wrap so "N missed" never hides). The break can fall between "1" and "missed".
- Fix (smallest): non-breaking spaces: the dot stays with the time and "1 missed" moves to line 2
  as one piece: `'${_statusLine()}\u00A0· '` and `L.t.missed(n).replaceAll(' ', '\u00A0')`. No `.arb`
  change. Listed old-test change: `test/calls_group_171_test.dart` (285 text now has the no-break spaces).
- Test: a widget test at the C71 width: the missed span text has no plain space; the line still
  ends "1 missed"; old 285 tests unchanged.

## B. My links: kiran and ayesha both on the right, ayesha's line runs under kiran (issue 5) - FIX
- Cause (VERIFIED with the maths): `lib/features/admin/presentation/widgets/link_balance_298.dart`
  `balance()` counts EVERY person as left or right of You (`dx < self.dx`). One offline person
  (sumaira) is placed straight above You (`link_paths_map.dart` `_placements212`, angle 270 deg),
  and `cos(270 deg)` = -1.8e-16, so her x is You's x minus a rounding speck -> she counts as LEFT.
  Count = left 1 / right 2 = "already balanced", so nobody moves: kiran and ayesha stay in the
  local Wi-Fi corner (down-right) and ayesha's line passes under kiran's name.
- Fix (smallest, NOT a sha-locked file): in `balance()`, a person within 1 px of You's x counts on
  neither side. Then left 0 / right 2 -> one moves left -> one person each side of You.
- Tests: offline one straight above + 2 local Wi-Fi -> one each side; the old `mini_map_298`,
  `link_apart_291`, `bundle273_my_links`, `own_links_308` tests unchanged and passing.

## C. My links: the line and its moving dot run over the "Server" name (issue 4) - NEEDS OK
- Code: `link_paths_map.dart` (sha-locked part, test `link_paths_zoom_222_test.dart`):
  `_plainLabel(canvas, sv + Offset(0, r + 10), 'Server', ...)` paints the name just under the
  cloud; the server line leaves the cloud down-right toward You, right through the name.
- Fix: on the small map only, a small card-coloured pill behind the "Server" name, drawn AFTER the
  lines and moving dots, so they pass behind it (big admin map unchanged).
- User OK given 15 Nov ("Yes, allow it"): sha-locked edit allowed for THIS only; new sha in
  `test/link_paths_zoom_222_test.dart` with the comment "313 (C): pill behind Server name".

## Not bugs (no change)
- Issue 1 (round button over kiran's call button): the list already has 96 dp room at the end
  (`calls_screen.dart` l.264, Bundle 255 B4) and the button can be moved (Bundle 206). The screenshot
  is mid-list; at the end of the list the last row is clear.
- Issue 3 (calls "No answer"): the user says the phones rang, nobody answered. Correct.
- Issue 6 (kiran / ayesha chats gone after uninstall + reinstall): by design.
  Uninstall deletes the phone's chats (`allowBackup="false"`). After the reinstall the app
  downloads from the server only what went through the server (`/api/v1/sync`). sumaira's chat
  went through the server, so it came back. kiran's and ayesha's chats went over Local Wi-Fi
  and never reached the server (Bundle 205: the server copy is only sent if there is no "got it"
  after 15 s), so they are gone from this phone. Calls came back because every call is saved on
  the server (`/api/v1/calls/reconcile`). kiran's and ayesha's phones still have those chats.

## D. Get chats back from friends' phones (NEW) - user picks 15 Nov
Picks: text + voice notes; automatic after a reinstall + a Settings button; the friend's phone sends
by itself (no pop-up); 1-to-1 AND group chats. Freeze ON: plan only.

### D1. Why it is needed (code)
- Uninstall wipes the phone (`AndroidManifest.xml` `allowBackup="false"`). `/api/v1/sync` gives back
  only what went through the server. Local Wi-Fi / mesh messages exist only on the friend's phone.
- The phone keeps its id after a reinstall (sumaira's server chat came back to the same id), so the
  friend's phone knows who is asking.

### D2. Safety rules (no weakening)
- Phone-to-phone ONLY over the existing locked link (`SealingPeerTransport`). Never the server.
  A packet must arrive with `event['sealed'] == true` (like `reach_check_296.dart` l.116); a phone
  that can't seal for me (`isSealCapable` false) is never asked and never answers. Unsealed = dropped.
- 1-to-1: the asker must be a FRIEND (contact, trusted, not blocked) opened with the friend's own
  saved key (no `_locked_spk` stranger key). The giver sends ONLY messages whose two ends are
  exactly {giver, asker} (`messagesFor(asker)`), never anyone else's chat.
- Never sent: deleted / cleared messages (they are not in the normal tables - 221 moves them to
  hidden tables; hidden tables, Get chat copies and admin copies are NEVER read), control bodies,
  the giver's file paths (`localPath` removed before sending).
- Saved on my side with `store.saveMessage` (already: one row per id, deleted/cleared never come
  back, status merge). No notification, no sound, no unread badge (marked read), no "got it" /
  read receipts sent back, no `_incoming` event.
- Limits: one restore session per asker per 10 min; packets <= 24 KB; one packet every 300 ms;
  at most 5000 messages per chat per session; at most 1 voice file at a time. Never at 10%
  battery or less (same rule as group catch-up G4).
- An old app (3.0.105 or older) ignores the new types (unknown type) - nothing breaks; it just
  can't give. kiran and ayesha must update before they can give your chats back.

### D3. How it works (1-to-1) - new `lib/features/messaging/data/services/chat_restore_313.dart`
Only what is missing travels (works the same after a reinstall or a normal update):
1. Me -> friend `restore_ask_313` {id}.
2. Friend -> me `restore_ids_313` {id, part, parts, ids:[...]} (ids only, oldest first, pages).
3. Me -> friend `restore_want_313` {id, ids:[up to 50 that I don't have]}.
4. Friend -> me `restore_msgs_313` {id, messages:[{id, sender_id, recipient_id, body, created_at,
   status, delivered_at, read_at, played_at, attachments(no local path)}]}; 3-4 repeat until done.
5. Voice notes (`contentType` audio/*): when the message is saved without the file, I allow the
   file (`allowIncomingFile`) and send `restore_file_313` {id, file_id}; the friend pushes it with the
   existing `files.sendDirectFile` (same as `_repushMedia`), one at a time. Photos / videos / files
   are NOT restored (they show as now: "not on this phone").
Checks on my side: every message must have sender/recipient = {me, that friend}, else dropped.

### D4. Groups
- Nearby groups: the existing G4 catch-up (`group_nearby_service.dart` `catchUpWith` / `_onHave`)
  already sends me the group card (I'm unknown -> `group_need`) and the last 7 days of signed
  messages when a member comes near. 313 adds a restore flag `r:1` on my `group_have` after a
  reinstall: the member then also gives OLDER messages from its group message table (from my join
  date, at most 2000) - same `group_give` packets, group lock (members who are not my friend can
  give too). Their writer signatures are only kept 7 days, so older ones are trusted from the
  member's phone (known limitation).
- Online groups: messages that went through the server come back by sync already. The rest is
  asked from friends who are members, with the same D3 steps plus `gid`; the giver checks we are
  both members of that group.

### D5. When
- Automatic: armed when the 313 code first starts and the phone has NO messages at all (a fresh
  install). A normal update (messages already there) is NOT armed. While armed (max 30 days), every
  friend / group member who comes near (`peer_connected` / `peer_discovered` / `route_recovered`,
  same events as G4) is asked once; no answer -> asked again after 10 min; done -> never again.
- Settings button (any time): Settings -> Chats -> "Get chats back from friends" asks every friend
  / member who is near now. Subtitle: "Waiting for friends nearby" / "Getting from kiran... 120 of
  450" / "Done". One toast per friend when > 0 came back: "Got 450 messages back from kiran".
  English + Urdu (LTR). A mock of this Settings row is shown before Build (UI match rule).

### D6. Files (planned)
- NEW `lib/features/messaging/data/services/chat_restore_313.dart` (+ test)
- `lib/app/app_dependencies.dart` (wire after `notifications`/messaging exist; transport events)
- `lib/core/services/local_store.dart` (light `messageIdsFor(otherId)`, `hasAnyMessage()`)
- `lib/features/groups/data/services/group_nearby_service.dart` (D4 `r:1`)
- `lib/features/home/presentation/screens/messenger_settings_screen.dart` (Settings row)
- `lib/l10n/app_en.arb`, `app_ur.arb` + gen; version 3.0.106+177

### D7. Tests
- Giver: unsealed / stranger / blocked / not friend -> nothing sent; only {giver, asker} messages;
  no deleted / hidden / control rows; no local paths; rate limit.
- Asker: wrong ends dropped; duplicates once; marked read; no notification / `_incoming`; voice file
  asked one at a time; photos not asked.
- Arming: fresh install armed, update not armed, 30-day end, done never again.
- Groups: `r:1` gives older messages only from my join date; non-member asks -> nothing.
- Old app ignores the new types (no crash).

### Known limitations (D)
- Messages I deleted "for me" before the reinstall can come back (my delete list was on the wiped phone).
- Restored messages are as true as the friend's phone (1-to-1 messages carry no signature).
- A friend who also reinstalled, or who deleted the chat, has nothing to give.

## E. Conversations page (owner) - from `Screenshot_20261115-233320.png` (C71, light)
User: "Check this page ui. Also show full text on every phone."
Files: `lib/features/admin/presentation/screens/admin_conversations_screen.dart`,
`lib/features/admin/presentation/widgets/conversations_kit307.dart`.

- E1. Title shows "Conversatio...": `_header` puts `Text('Conversations', maxLines: 1, ellipsis)` in a
  `Flexible` next to `ServerPill307` (30 px title + "Server connected" pill do not fit at 360 dp).
  Fix: title + pill in a `Wrap` (title never cut; when there is no room the pill moves under the
  title, left aligned). Same for "No server".
- E2. Grey square corners behind the Live card: `_carousel` wraps the card in `ClipRect` (for the
  swipe), which cuts the card's soft shadow into a hard rectangle. Fix: room for the shadow inside
  the clip (inner padding, outer padding reduced by the same amount: the card stays where it is).
- E3. "+ New request" text touches the right end of the button: `Fab307` = `IntrinsicWidth` around
  `BigButton307`, which has no side padding. Fix: 22 dp padding left and right inside the button
  (new optional `padH` on `BigButton307`, default 0 = other buttons unchanged).
- E4. "1 parts" in Finished (`_finishedRow` uses `tapToOpenParts307` "{n} parts"). Fix: "1 part" when
  n = 1 (new keys `onePart313` "1 part" / Urdu "1 حصہ", `tapToOpenOnePart313`), also on the request
  card and the answer viewer that use the same words.
- E5. Full text on every phone: this page has 20 `maxLines: 1` + "..." texts (12 in the screen, 8 in
  the kit). Names ("kiran & ayesha", groups, 3+ people), sub lines ("Waiting for their phones"),
  "Full chat" / ranges and the Finished line wrap to a 2nd line instead of "..."; the big Live line
  ("Sent to 2 phones") keeps its scale-down (already `FittedBox`). Chips, counts and tab labels stay
  1 line (short). Layout keeps working when a line wraps (rows grow, nothing overlaps).
- Tests: widget tests at 320 dp, 360 dp and 411 dp wide, text scale 1.0 and 1.3, light + dark, English
  + Urdu: no text cut (no ellipsis on the listed texts), no overflow; title always "Conversations";
  pill under the title at 320 dp; Fab text has 22 dp room; "1 part" / "2 parts". Old 307/310 tests
  unchanged except the ones that look for the 1-line title (listed when built).
- Not bugs: the "Live" heading half hidden under the tabs = the list was scrolled a little (normal);
  the same request in Live and In progress = the approved v2 design (Live = the big card).

## As built (3.0.106+177) - where the build differs from the plan above
- D2/D3 sending: restore packets go out ONLY with `SealingPeerTransport.sendLockedOnly313` (never the
  plain fallback of `send`). They travel as `sealed_x` (not queued): if the friend drops off mid-way a
  packet is lost; the asker asks the missing ids again ONCE, then the session ends and the friend is
  asked again 10 min after its last packet.
- D3 packets: `restore_ask_313` {id, chats:["d", gid...]} -> `restore_ids_313` {id, chat, ids (300 a
  page), last} -> `restore_want_313` {id, chat, ids (50)} -> `restore_msgs_313` {id, chat, items, last}
  (<= 24 KB) -> `restore_file_313` {id, file_id} for voice notes, one at a time (max 200).
  Incoming packets are handled one after another (`_chain`) - handling them in parallel lost
  messages in the test (156 of 424 saved).
- Giver: one session per asker per 10 min (`giveGap`); not at 10% battery or less; friends only.
- D4 groups, two ways (both dedup by message id):
  1. nearby group catch-up: `group_have` carries `r:1` while armed; the member gives up to 2000
     older words-only messages from my join date, inside the group lock, without signature
     (`restoreMax313`); never passed on to other members;
  2. a friend who is in the same group gives that group's messages with the D3 steps (chat = gid).
  After restored group messages are saved, `GroupChangeHub.changed(gid)` -> the list reads again.
- D5 arming: `ChatRestore313.armAtLaunch` runs right after the database opens (before sync), in
  `local_link_app.dart` (failure logged `RESTORE313_ARM_FAILED`). It arms 30 days only if the phone
  has no messages AND the setting `restore313_until` was never written. A normal update never arms.
- D5 Settings: own group "Chats" placed before "This phone", row "Get chats back from friends"
  (`RestoreChatsRow313`). Toast on Home when messages came back (`ChatRestore313.lastDone`).
  The Settings-row mock was NOT shown (user said "Build" without it).
- D6 files (actual): NEW `chat_restore_313.dart`, NEW `chat_restore_store_313.dart` (LocalStore
  adapter), NEW `restore_chats_row_313.dart`; `local_store.dart` (`hasAnyMessage313`),
  `sealing_peer_transport.dart` (`sendLockedOnly313`), `reliable_messaging_service.dart`
  (`pushRestoredFile313`), `group_nearby_service.dart` (`r:1`), `app_dependencies.dart`,
  `local_link_app.dart`, `home_screen.dart`, `messenger_settings_screen.dart`, `.arb` (12 keys) + gen.
- E4: the request card (`request_step_307.dart`) and Finished say "1 part". The "x of y parts" lines
  only show while parts < y, so y >= 2 there; the answer viewer "0 of 1 parts" while nothing came yet
  is left as is.
- E5: chips may wrap (a long Urdu chip on a 320 dp phone); the meta line (chip + range + Cancel) is a
  `Wrap`. Fixed-height items (tab segment, blue buttons) scale the words down instead of "...". The
  search box hint stays Flutter's one-line field (not cut in any tested size).
- Extra fix found by the new test: a store list that can't be sorted no longer stops the ask.

## Regression (when built)
Full app suite + analyze (361 old issues, 0 new); phone: Calls rows, My links with 1 offline + 2 live.
