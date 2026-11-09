# ONE TODO - all remaining phases, nothing "later" (updated 2026-11-09)

**Status: FREEZE OFF (your go ahead for ALL phases): build phase after phase without stopping. Mocks are made and built at once (you check at the end). Parts that need your logs / details are skipped and listed at the end. Result = ONE app zip + ONE backend zip.**

## Your answers (2026-11-09)
- "Nothing later, do everything now." All the old "do later" items are active phases now:
  - block fix, video issue, Wi-Fi call gaps, Realme mic, ZTE day test;
  - mesh voice, video call (paused), group voice;
  - notification picture, My QR place;
  - old offline admin row, rename password check;
  - the 228 idea, how 3.0.63 got onto the C71.
- Decisions: **use my advice** for all of them (listed in "Decisions taken" below).
- Base: build on top of the **235 zip now** (no waiting for your push). When you push 235, I check it matches.
- Testing: kept out of this list, as you asked earlier. Each phase still gets its own `APPLY_NNN.md` with steps.
- Video: you also said "keep video out", but your list names the video issue and the paused video call, so they are in (phases 11 and 12). Say if you want them out again.

## Rules for every phase
- I build the phases in this order, one zip per phase. Each zip is ONE commit, on top of the one before.
- A phase that changes a screen gets a mock first. I show it and wait for your OK before building that screen.
- If the server changes, there is a separate backend zip that you deploy first.
- I tell you about any old test that has to change.
- No push until you say.

## Order at a glance
| # | Phase | Bundle | Who | Server change? | Mock? |
|---|---|---|---|---|---|
| 0 | Deploy + push 235, secrets cleanup (P0) | - | you | - | - |
| 1 | Friend on a new phone = one chat | 237 | me | yes | no |
| 2 | Offline account goes up by itself | 236 | me | yes | no |
| 3 | Block fix, rename freeze, old admin row | 238 | me | yes (admin row) | yes (Show hidden switch) |
| 4 | Status colour fix (S5 A) + link count log (S6) | 239 | me | no | no |
| 5 | C71 <-> Note 60x acks + link key (Phase 8 P) | 240 | me | no | no |
| 6 | Voice: Wi-Fi call gaps + Realme mic | 241 | me | no | no |
| 7 | Notification picture + My QR place | 242 | me | no | yes |
| 8 | HTTPS for the server (S3 A+B) | 243 + 244 | me | yes | small (message) |
| 9 | Security code for contacts (S7) | 245 | me | no | yes |
| 10 | Tidy repos + key warning (S10) | 246 | you + me | yes (files only) | no |
| 11 | Video issue (193 logs) | 247 | me | no | no |
| 12 | Video call (paused) brought back | 248 | me | no | yes |
| 13 | Mesh voice calls (A -> B -> C) | 249 | me | no | maybe |
| 14 | Group voice call | 250 | me | maybe | yes |
| 15 | Online voice calls through the server (P9) | 251 | me | yes (voice relay) | yes |
| 16 | ZTE full-day check | - | you + me | no | no |
| 17 | How 3.0.63 got onto the C71 | - | me | no | no |
| 18 | The 228 idea | 252 | me | ? | ? |
| 19 | Turn plain HTTP off (S3 C) | 253 | you + me | yes | no |
| 20 | Code structure cleanup (S11) | in each bundle | me | - | no |
| 21 | Problems from your 23:07-23:13 screenshots (do 21.3 first) | 254 | me + 2 logs | maybe | yes (row text + Cancel) |

Bundle numbers from 238 on are my suggestion. They move up by one if a phase is split.

---

## PHASE 0 - Finish 235 (you; the code is already written)
Files: `locallink_backend_230-231-235_2026-11-09.zip`, `locallink_app_235_2026-11-09.zip`, `APPLY_235.md`.

### 0.1 Backend
- [ ] Back up `data\locallink.db`.
- [ ] Run this count:
  `sqlite3 data\locallink.db "SELECT COUNT(*) FROM devices WHERE COALESCE(user_id,'')='' AND COALESCE(status,'active')='active';"`
  If it is above 0, set `LOCALLINK_ALLOW_DEVICE_ONLY=true`.
- [ ] `Expand-Archive -Force` the backend zip, then build and restart the server.

### 0.2 App
- [ ] `Expand-Archive -Force` the app zip, then `flutter pub get` and `flutter build apk`. Install 3.0.72+143 on all phones.

### 0.3 Push
- [ ] Push the backend, then the app (commands are in `APPLY_235.md`). Then say "I pushed".

### 0.4 P0 secrets cleanup (CRITICAL)
- [ ] Make the backend repo private.
- [ ] Remove `data/*.db` (+ `-wal`, `-shm`) from the whole git history (filter-repo).
- [ ] Run `--reset-admin` and set a new admin password.
- [ ] Give users new passwords and new recovery codes.
- [ ] Revoke old sessions.
- [ ] Set `LOCALLINK_PAIRING_CODE` on the live server.
- [ ] Add `data/` and `*.db*` to the backend `.gitignore`.

---

## PHASE 1 - Bundle 237: a friend on a new phone keeps ONE chat
Plan: `TODO_237.md`. Version 3.0.73+144. App DB stays 34.

**Example:** Ali gets a new phone and signs in as @ali.
- Today: an empty chat.
- After 237: one Ali row, with old and new messages together.

**Cause:** messages are saved by phone id, and a contact keeps only one phone id. Re-adding a contact wipes the custom name and the private mark.

### 1.A Remember a friend's old phones
- [ ] New file `lib/core/services/person_phones_237.dart`. It stores, in settings key `person_phones_237`, up to 10 old phone ids per user id, with the time.
- [ ] Learn old ids only from `saveDirectoryProfile` (same person, other phone), `addContact`, and the server's `past_device_ids`.
- [ ] A phone that is now another person's current phone (235 "New owner") is taken out.

### 1.B One chat per person (read only)
- [ ] `history()` and `cachedHistory` load the current phone plus the old phones (only messages with me).
- [ ] The Chats list: `userIdForDevice` resolves old ids, and `_collapseDeviceDuplicates` makes one row. The preview is the newest message; the unread count is the sum.
- [ ] Mark read, Clear and Delete apply to all his phones. Deleted stays deleted.
- [ ] A message still waiting for the old phone is sent once to the new phone. New sends go to the current phone only.

### 1.C Re-add keeps the details
- [ ] `addContact` keeps `custom_name`, `is_private` and `added_at`.
- [ ] Adding someone already in your contacts opens the same chat.

### 1.D Server
- [ ] `internal/httpapi/contacts.go` (`accountContactsForUser`) adds `past_device_ids`: newest first, max 10, never the current phone, contacts only.

### Files
- **App:** `person_phones_237.dart` (new), `local_store.dart`, `account_restore.dart`, `directory_repository.dart`, `reliable_messaging_service.dart`, `messaging_repository.dart`, `message_delete_actions.dart`, `home_repository.dart`, `home_screen.dart`, `app_build.dart`, `pubspec.yaml`.
- **Server:** `contacts.go`.

### Limits
- My own new phone is not covered.
- A friend who was only ever offline joins after one of you reaches the server.
- Deleted stays deleted.

---

## PHASE 2 - Bundle 236: an offline account goes up by itself
Plan: `TODO_236.md`. Version 3.0.74+145.

**Example:** Sara made @sara offline, and the phone lost its saved password.
- Today: "Publish your account - confirm your password".
- After 236: nothing is asked.

### Steps
- [ ] **B1:** remove `_maybeOfferPublish` and `_showPublishSheet` in `home_screen.dart`. The banner "Publish" runs `autoPublish(from: 'banner')` with a spinner.
- [ ] **B2 (app):** with no saved password, send the saved salt + hash + iterations, `offline_user_id` and the recovery code. Never the plain password.
- [ ] **B2 (server, `auth.go`):** new fields `password_hash`, `password_salt`, `password_iterations`.
  - Accepted only with an `offline_...` id and an empty password.
  - Size checks; iterations 100000-2000000; re-hashed to 600000 at login.
- [ ] **B4:** offline-made sign-ups skip `LOCALLINK_PAIRING_CODE` (`auth.go`, `join_relay_222.go`). The app stops asking for the code for an offline account.
  - **Risk:** anyone can claim "made offline".
- [ ] **B5:** old server -> quiet retry + "Waiting for the server to be updated." (`join_cards218.dart`).
- [ ] 235 stays (a known phone still gets "Confirm your account"). 234 B3 is NOT brought back.

---

## PHASE 3 - Bundle 238: block fix + rename freeze + old admin row

### 3.1 Block fix (`BLOCK_STATE_SKIPPED`) - my advice: fix it
- [ ] Find the exact cause: where `BLOCK_STATE_SKIPPED` is logged, and which case skips a real block or unblock.
- [ ] Fix it so a block or unblock always reaches all phones (the 212 rule), and a skipped update is retried when the link or server comes back.
- [ ] Log `BLOCK_STATE_APPLIED` / `BLOCK_STATE_RETRY`.

### 3.2 Rename confirm freezes slow phones
- [ ] `home_screen.dart`: move the password check off the screen thread into a background isolate, like the login lock.
- [ ] A spinner on the button while it runs. Same texts.

### 3.3 Old offline row of a cleared phone stays in Admin -> Users - my advice: hide after 30 days
- [ ] Server + app admin list: an offline-only row that hasn't been seen for 30 days is hidden. It stays in the DB.
- [ ] A "Show hidden (N)" switch at the bottom of the list, in the app and on the web. **Mock first.**

---

## PHASE 4 - Bundle 239: status colours (S5, option A) + link count log (S6)
- [ ] `lib/core/models/device.dart`: `'yellow'` -> `serverConnected`. Today "server connected" is read as disconnected. The animated line is not changed.
- [ ] `LocalLinkTransportService.kt`: one daily line `LINK_AUTH_DAY verified=<n> legacy=<n> rejected=<n>`. Strict mode stays OFF, because it would break offline first contact.

---

## PHASE 5 - Bundle 240: C71 <-> Note 60x messages not confirmed + link key (Phase 8 P)
- **What we know:** on 11-07 there were 922 sends with 0 acks, and a 32 KB file was stuck for 11 h, with `LINK_AUTH legacy reason=no_local_key`. 224 already stopped the foreign Realme groups.
- [ ] First I read the newest Note 60x and C71 logs in `uploads/` (`RMX3938-2026-11-09-2108`, `RMX5303-2026-11-09-2109`) for acks and the `LINK_AUTH` lines.
- [ ] If those logs don't show the drop, I need the Note 60x log from 11-07. Any new log with both phones together for 1 h also works.
- [ ] Fix the side that drops or loses the acks:
  - an ack must go back on the same link the message came in on;
  - a resend stops once an ack arrives;
  - a stuck file restarts from the last good part.
- [ ] Link key (Phase 8 P): after a pair, both phones save the shared link key, so `no_local_key` stops. This never calls `pushLinkKeys` with only one key.

---

## PHASE 6 - Bundle 241: voice call quality (Wi-Fi gaps + Realme mic)
- [ ] **Wi-Fi call gaps:**
  - read the call logs in `uploads/` (jitter, late packets, buffer level);
  - find where the sound stops: network, jitter buffer, or the phone sleeping the Wi-Fi;
  - fix that one cause (for example a slightly bigger jitter buffer on Wi-Fi Direct, or keeping Wi-Fi awake during a call);
  - the rejected "speaker backlog skip" is not used.
- [ ] **Slow Realme mic:**
  - open and warm up the mic during ringing, so the first words aren't lost;
  - calls stay on speaker;
  - log `CALL_MIC_READY ms=`.
- [ ] If the current logs don't show the cause, I tell you exactly which call to record.

---

## PHASE 7 - Bundle 242: notification picture + My QR place (mock first)
- [ ] **Notification picture (my advice: yes):** the sender's photo appears on the right of the message notification.
  - Private, or no photo -> a letter circle.
  - The photo is read from the local cache only (no network).
- [ ] **My QR (my advice):**
  - a QR icon at the top right of Add Contact -> opens My QR;
  - a QR icon on the profile card in Settings;
  - the current place stays too.
- [ ] Mock with both, then build after your OK.

---

## PHASE 8 - Bundles 243 + 244: HTTPS for the server (S3 parts A + B)

### 8.A Server
- [ ] `LOCALLINK_TLS_AUTO=true` makes a self-signed certificate in `data/tls/` (ECDSA P-256, LAN IPs + localhost, 5 years).
- [ ] HTTPS on 8443, HTTP stays on 8080.
- [ ] Pairing info adds `tls_port` and `tls_cert_sha256`, signed by the 231 proof (`ll-pair-v2|…`). Discovery adds `tls_port`.

### 8.B App
- [ ] New `pinned_http_overrides.dart`: accept only the pinned certificate hash, for the pinned host and port. It covers the API, all `http` calls and the WebSocket.
- [ ] At pairing: pin it and switch to `https://` / `wss://`.
- [ ] A changed certificate is refused: "Server certificate changed. Reset setup to trust it".
- [ ] An old server without TLS still works over HTTP.

---

## PHASE 9 - Bundle 245: security code for contacts (S7, mock first)
- [ ] `safety_number.dart`: 12 groups of 5 digits from both signing keys, plus a QR.
- [ ] The contact info sheet gets a "Security code" card: scan or "Mark as verified".
- [ ] A key change shows the chat line "<name>'s security code changed" and calls `markChanged()`, so the call warning works.
- [ ] A reinstalled friend: the new key is used only after "Accept new code" (or the server's key history).

---

## PHASE 10 - Bundle 246: tidy repos + key (S10) - my advice: keep the debug key
- [ ] **You:** back up `C:\Users\sajjad Ahmed\.android\debug.keystore` (USB + cloud).
- [ ] **Me:** `build.gradle` prints a clear warning when it uses the debug key.
- [ ] **Me:** delete `web/admin.html`, `test_output.txt` and `tmp_test.ps1`; move scripts to `tools/`; move old APPLY/TODO files to `docs/history/`.

---

## PHASE 11 - Bundle 247: video issue (193 logs)
- [ ] I re-read the bundle 193 notes and logs and write the cause in plain words.
- [ ] Fix only that cause, with the smallest change. (The earlier "Video: no fix" stays true for anything not proven by the logs.)

## PHASE 12 - Bundle 248: video call (paused) brought back
- [ ] Plan first (`TODO_248.md`): what was paused, and what still blocks it (camera on the ZTE's 2 GB, Wi-Fi Direct bandwidth).
- [ ] Mock if a screen changes. Then build, with the video switch staying the same as today.

## PHASE 13 - Bundle 249: mesh voice calls (A -> B -> C)
- [ ] Plan first (`TODO_249.md`). Voice packets travel through B the way messages do, at most 1 middle phone.
- [ ] B forwards without decoding, and the call stays sealed end to end.
- [ ] B shows nothing, but its battery use is limited.

## PHASE 14 - Bundle 250: group voice call
- **Note:** this reverses your earlier rule "no group voice call". It's here because you listed it.
- [ ] Plan + mock first (`TODO_250.md`): up to 4 people, Wi-Fi Direct / LAN first. Each phone sends to each other phone (no server needed).
- [ ] If the ZTE can't take it, it's limited to 3.

## PHASE 15 - Bundle 251: online voice calls through the server (P9)
- [ ] Plan first (`TODO_251.md`): a server voice relay for friends who are not nearby. Sealed audio; the server only passes packets.
- [ ] Server: a relay endpoint with limits per user. App: try nearby first, then the server.
- [ ] Mock for the "Calling over internet" line.

## PHASE 16 - ZTE full-day check (you + me)
- [ ] **You:** use the ZTE normally for one day with LinkUp, then send the log + the battery screen.
- [ ] **Me:** check battery use, background kills (`com.zte.heartyservice`) and Nearby wake-ups, then fix what shows up.

## PHASE 17 - How 3.0.63 got onto the C71
- [ ] **Me:** check the C71 logs for the version stamps and update events (APK share from a nearby phone, or a manual install). Explain in plain words; no code unless something is wrong.

## PHASE 18 - The 228 idea
- [ ] My notes only say "228 is already offered". The details were lost. **Tell me in one line what 228 was**, and I plan it (`TODO_228.md`) and build it here.

## PHASE 19 - Bundle 253: turn plain HTTP off (S3 part C)
- [ ] As soon as every phone runs the HTTPS version (I check the admin "Version" page with you): set `LOCALLINK_HTTP_PORT=off` and build without `LOCLINK_ALLOW_INSECURE_HTTP`.

## PHASE 20 - Code structure cleanup (S11)
- [ ] Inside each bundle above: when a file is touched anyway, move one shared type to `lib/core/contracts/` or break one feature cycle. Never a big separate bundle.

---

## PHASE 21 - Problems seen in your screenshots (2026-11-09, 23:07-23:13) - FREEZE ON, needs go ahead
Bundle 254. Screens: Admin (`Screenshot_20261109-231356.png`), Admin actions (`...-231322.png`), chat with noshad (`...-230736.png`).
Checked in the code (app = 3.0.71 + 235 patch, commit 619dfd0) and in the 9 Nov logs (C71 = sajjad/admin `...da19f3`, 20:09-21:09; Note 60x = noshad `...d181c0`, 20:08-21:08).
Status words: CONFIRMED = seen in code or logs. LIKELY = code points to it, logs after 21:09 needed. BY DESIGN = the code does what we planned.

### 21.3 "No phone reached yet" while noshad WAS near (CONFIRMED - main problem, do first)
- Cause (Note 60x log): the cards DID reach noshad's phone over Wi-Fi Direct, but his phone threw them away every minute:
  `ADMIN_ACT_REJECT reason=no_trust id=3f744a from=da19f3` (and `b5c80f`), 14 times, 21:03-21:08.
- `no_trust` = noshad's phone has no saved server key (`server_trust_key`), so it cannot check an admin card (`AdminActionService.check()`, admin_action_service.dart line ~428, reads `AdminBlockService.serverKey`).
  The same log shows `ADMIN_ACT_SYNC_SKIP Server address is required` and `OFFLINE_ACCOUNT_PROBE fail` -> this phone has not reached the server with its current account (new offline account 4073e7, made after the old 01561c).
- This is YOUR safety rule ("a phone must reach the server once before it trusts admin cards"), so it is right to refuse. The bug is that nobody is told:
  - the admin sees "no phone reached yet" although the phone got the card;
  - noshad sees nothing;
  - C71 re-sends the same 2 cards every 60 s (`digestEvery`) and noshad's phone re-checks and logs them every 60 s.
- Fix steps:
  - [ ] Receiver (`_onCards` / `offerCard` -> `check()` == `no_trust`): keep the card id in a small "waiting for trust" list (max 200, in memory + setting `admin_act_wait_trust`), log `ADMIN_ACT_WAIT_TRUST` ONCE per card, and re-check these cards right after `pinTrust()` saves a key (`TRUST_KEY_SAVED`) -> the card then applies with no new copy needed.
  - [ ] Receiver sends back a signed "seen" note (same `AdminActionDone` format, `result='wait:no_trust'`). It does NOT count as done (`_recount` skips results starting with `wait:`).
  - [ ] Admin screen (`adminActionLook`, admin_actions_screen.dart end of file): when a `wait:` note is there, show "Reached noshad's phone - it must reach the server once" instead of "no phone reached yet".
  - [ ] Sender digest: do not re-send a card to a phone that already said `wait:no_trust`, until that phone's digest changes.
  - [ ] Receiver: also log `ADMIN_ACT_NOT_MINE id=..` once when no box opens (today `_applyOnce` returns silently at "not for me"), so the next logs show it.
  - [ ] Noshad's phone (no code): open LinkUp once while on the server's Wi-Fi so it saves the key.
- Tests: card with no trust -> wait note sent, not counted; trust saved later -> card applies by itself; admin row text; no re-send every minute; old tests unchanged.

### 21.1 Admin actions: Block / Unblock pile up (CONFIRMED)
- Cause: `AdminActionService.make()` (admin_action_service.dart ~line 788) never looks for an older pending card for the same person. "Replaced" only comes from the server (`takeState`), so with no server Block, Unblock, Block, Unblock all stay pending. Each one also counts toward the 50 limit (`maxPendingPerAdmin`, `pendingMine`).
- On the target phone the order is safe for Block / Unblock: `doers.block(inner)` uses the 212 block record version, so an older card arriving late changes nothing.
- Fix steps:
  - [ ] In `make()`, for actions in the same family (block / unblock, and off / active) and the same `targetUserId`: find my pending entries and close them with a signed cancel card (the same path as `cancel(id)`, reason `replaced`). Their rows move to Done as "Replaced".
  - [ ] The newest card is the only pending one, so the list shows one line per person.
  - [ ] Server copy: when the server is back, the server's own "replaced" state still wins (no change there).
- Tests: Block then Unblock offline -> 1 pending (Unblock) + 1 replaced; limit counts 1; a late older card on the target does nothing.

### 21.11 Extra bug found while checking 21.1: Off / Active can apply in the wrong order (CONFIRMED in code)
- `_doIt` case 'off' / 'active' calls `doers.setClosed(closed)` even when the inner block record is older than the one the phone already has. So an old "Off" card that arrives after a newer "Active" card closes the phone again.
- Fix:
  - [ ] Save the card time of the last Off/Active applied (setting `admin_closed_at`), and skip (result `already`) when the card is older.
- Test: Active (new) then Off (old) arrive -> phone stays open.

### 21.2 "Get chat - noshad & noshad" (CONFIRMED)
- Cause: C71 knows TWO noshad accounts, both named "noshad", on the SAME phone `...d181c0`: old account 01561c (card saved 20:59) and new account 4073e7 (card saved 21:09) (C71 log `DIR_PUBLIC_CARD`). This is the duplicate-account case that 235 blocks.
- `HiddenStore221.people()` (hidden_store_221.dart ~line 887) lists every `directory_profiles` row by name only, with no @username and no "same phone" check. The picker (admin_chat_request_sheet.dart `_pickFrom`) only refuses the same id, not the same phone, so "noshad & noshad" was allowed. The label is built as `'${a.name} & ${b.name}'`.
- Fix steps:
  - [ ] `people()`: also return `device_id` and `username`; when 2 accounts share one phone, keep the newest as normal and mark the older "old account".
  - [ ] Picker rows show the name + `@username` (+ "old account" in grey).
  - [ ] `_ready` refuses 2 accounts on the same phone, with the note "These two accounts are on the same phone."
  - [ ] Label: when both names are the same, use `@usernames` ("@noshad & @noshad2").
  - [ ] After 235 is on both phones, the second account on one phone is blocked anyway (no extra work).
- Tests: two profiles on one device -> one marked old; same-phone pick refused; label uses usernames.

### 21.4 Status does not match between screens (CONFIRMED - you said the link did not drop 23:07-23:13)
- Chat header ("Nearby - Wi-Fi Direct") comes from `PresenceHub` (live route: `wifi_direct`; `local_net` (linked group / hotspot) also shows "Wi-Fi Direct"; it looks at ALL phones of the person).
- Admin ("No link", "0 Phones near", map "No other phones linked") comes from `_onLink` in admin_panel_screen.dart (~line 387): only the saved device rows (`wifiDirectConnected` / `meshAvailable` / `lanAvailable`, or presence in the last 4 min). A `local_net` link does not set those flags, so the admin says "No link" while the chat says "Wi-Fi Direct".
- Admin cards themselves are sent by a third source (`link.topology()` peers), which is why the cards still reached noshad (21.3) while the admin screen said "No link".
- Fix steps:
  - [ ] `_onLink`, `_offlineWay`, `_tagFor` ask `PresenceHub.instance` first (`isReachable`, `wayOf`), saved flags only as backup. Admin, map and chat then give the same answer.
  - [ ] Small extra: `_blockedIds` compares USER ids with DEVICE ids (`_blockedIds.contains(d.id)`), so it never matches; compare with the device's user id.
- Tests: peer on `local_net` / `wifi_direct` in PresenceHub with no saved flag -> admin shows "Wi-Fi Direct", 1 phone near, map node; blocked person hidden.

### 21.12 "Get chat - 7 days" (noshad & noshad) never answers (CONFIRMED in code)
- Two reasons, both must be fixed:
  1. Noshad's phone refuses admin cards with `no_trust` (21.3). The 9 Nov log shows this for the 2 sign-out cards at 21:03-21:08; your get_chat was made later (after the log ends), so it is the same cause unless the next logs say otherwise.
  2. Even WITH trust it can never answer: the request was "noshad & noshad" = 2 accounts on the SAME phone (`...d181c0`). `_resolve` (chat_answer_reader.dart ~line 624) turns it into devices = [d181c0] only, and `rows()` (hidden_store_221.dart ~line 437) asks for messages `sender IN (d181c0) AND recipient IN (d181c0) AND sender<>recipient` -> always 0. Then `buildChat` throws `no_copy_here`, `ChatDoer221` re-throws it ("another phone answers"), `_applyOnce` logs `ADMIN_ACT_DO_FAIL` and tries again later, forever. No receipt, so the row says "no phone reached yet" for ever.
- Fix steps:
  - [ ] 21.2 picker: two accounts on one phone can't be picked together (stops this request at the start).
  - [ ] Request check (`request()`): refuse when both people resolve to the same phone(s): "These two accounts are on the same phone - there is no chat between them."
  - [ ] Answer side: when a target phone has no copy, it sends a signed receipt `result='empty'` (not an answer). When EVERY target phone said `empty`, the row moves to Done as "No messages in this chat (7 days)". If one phone still may have a copy, the row stays pending.
  - [ ] Log `CHAT_REQ_EMPTY id=.. range=7` once instead of `ADMIN_ACT_DO_FAIL` every minute.
  - [ ] Your old "noshad & noshad" rows: cancel them (tap row -> Cancel), or they close by themselves as "No messages" after this fix.
- Tests: same-phone pick refused; target with 0 messages -> `empty` receipt -> Done "No messages"; 2 targets, 1 empty + 1 answer -> the answer shows; no retry loop.
- Your answer: you wanted the chat between noshad and YOU (sajjad).
  - The right pick is "First person = sajjad (top of the list), Second person = noshad". Then the devices are your C71 + noshad's phone, and noshad's phone sends its copy (including the messages he deleted) once it has trust (21.3).
  - [ ] Picker: the top row reads "Me (sajjad)" with a "Me" tag, so it can't be missed; the two noshad rows show @username + "old account" (21.2).
  - [ ] Request sheet note when "Me" is one of the two: "You already have this chat. Their phone adds the messages they deleted."
  - Test: Me + noshad -> targets = noshad's phone only; label "sajjad & noshad".

### 21.5 Map: "You" shows "Y" in pink (CONFIRMED)
- Cause: link_paths_map.dart ~line 515: the "You" node is drawn with `name: 'You'`, so the avatar takes the letter "Y" and a colour from that word. The top card uses your real name ("S", purple).
- Fix:
  - [ ] Pass `selfName` (your name) to the avatar; keep the label under it as "You". The map and the top card then show the same photo / letter / colour.
- Test: map self avatar letter = first letter of the username.

### 21.6 Map title "Link paths": the "L" is cut off (CONFIRMED)
- Cause: `AdminCard216` (admin_kit216.dart ~line 318) puts `ClipRRect(radius 15)` INSIDE the padding. The rounded clip is applied to the content box, not the card, so whatever sits in the top-left corner of the content (the "L") is cut by the curve. Any padded admin card can do this.
- Fix:
  - [ ] Clip the card itself (`Container(clipBehavior: Clip.antiAlias, ...)` with the same rounded border) and drop the inner `ClipRRect`. Nothing else moves.
- Test: golden/size check that the title's left edge is inside the card and not clipped.

### 21.7 Map: the line to the Server while there is no server (BY DESIGN - no change)
- Code (link_paths_map.dart `_dashedServerLink`): with no server the You-Server line is drawn STILL, red + grey dashes (217: "unmistakable", no motion). The moving dashes are only on live links.
- Your rule: "Don't change animated line". So no change.
- [ ] Only if you see it really moving on the phone: send a short screen video and I will check again.
- [ ] Optional (small): the small map writes "Server - offline" under the cloud, like the full map already does.

### 21.8 Admin actions: the orange banner is cut at the top (LIKELY)
- Cause: the banner is the FIRST item of the scrolling list (admin_actions_screen.dart ~line 195) and the list has 0 top padding (`AdminPage216`, admin_kit216.dart ~line 61). A small scroll or the pull-to-refresh hides its top under the title bar.
- Fix:
  - [ ] Pin the banner under the title bar (outside the list) with 8 dp top space, so it never scrolls away.
- Test: banner is outside the list and fully visible after a scroll.

### 21.9 Stop a pending action (BY DESIGN, but hidden)
- Cancel already works: tap a pending row -> "Cancel this action?" -> `service.cancel(id)` (works offline with a signed cancel card). But the row shows only "Pending", with no arrow or hint, so you could not know.
- Fix:
  - [ ] Pending rows that can be cancelled get a small "Cancel" text on the right (or "Tap to cancel" under the name). Mock first.
- Test: the Cancel text shows only on rows where `canCancel` is true.

### 21.10 Read ticks stay grey (NEEDS LOGS)
- What I found: C71 sent a read note for noshad's messages (`READ_RECEIPT_SENT chat=d181c0` at 21:07:43). Noshad's phone sent NO read note at all up to 21:08 (no `READ_RECEIPT_SENT`).
- Read notes are sent only when: the chat is opened (`markDirectConversationRead`), a message arrives while that chat is open, or Mark as read / Reply in the notification. Read receipts OFF on that phone = never.
- Likely tied to 21.2: noshad's phone changed account; your messages were sent to the old account (01561c) on the same phone, so under the new account they may not be in the chat he opened.
- [ ] Check noshad's Settings > Privacy > Read receipts.
- [ ] Logs of both phones after 21:09 (look for `READ_RECEIPT_SENT` / `READ_RECEIPT_GOT`).
- [ ] Fix only when the logs show the cause.

### What I need from you for Phase 21
- [ ] Logs of BOTH phones for 9 Nov 21:09-23:15 (to finish 21.10 and to see the get_chat card id in 21.12). 21.4 no longer needs logs (you confirmed no drop).
- [ ] Noshad: open LinkUp once on the server's Wi-Fi (fixes 21.3 on his phone today).
- [ ] "Go ahead" for bundle 254 (freeze is ON). Mocks first for 21.3 (row text) and 21.9 (Cancel text).

---


## Decisions taken (your choice: my advice)
| Item | Decision |
|---|---|
| Status colours (S5) | Option A: one-line fix, dots unchanged |
| Old admin rows | Hidden after 30 days, "Show hidden (N)" switch |
| Block fix | Yes, fix it |
| Release key | Keep the debug key, back it up today |
| Plain HTTP off | Right after all phones run the HTTPS version (phase 19) |
| Server identity | Keep it (no re-pairing) |
| Strict link check (S6) | Stay off, only count |
| Notification picture | Yes, sender photo on the right (mock first) |
| My QR | Add Contact top right + Settings profile card (mock first) |
| 3.1 / 3.2 and D1 | Skip (my earlier advice) |

## Still needed from you
1. Phase 0: deploy, push, and the P0 cleanup.
2. Phase 5: the Note 60x log from 11-07, only if the 11-09 logs don't show the problem.
3. Phase 6: call logs, only if the current ones don't show the cause.
4. Phase 16: one day of ZTE use + its log.
5. Phase 18: what the 228 idea was.
6. Mock OKs: phases 3.3, 7, 9, 12, 14, 15.

## Left out (your earlier choice)
- All testing (phone tests, test runs, CI, replay tests). The ZTE day check stays in only because you listed it.
