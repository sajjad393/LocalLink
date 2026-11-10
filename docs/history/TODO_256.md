# TODO 256 - New phone (TECNO BG6) logs: sign-up, add friend, smaller crown

Log: `uploads/LinkUp-logs-TECNO-BG6-2026-11-10-1344.txt` (3.0.73+144, Android 13, 13:35-13:44, 2722 lines).
I read every line, and checked the code in app `0561b07` and backend `2416f0e`.
FREEZE ON: this is a plan only. Nothing is built until you say "go ahead 256".

Legend:
- CONFIRMED = seen in the log and in the code.
- LIKELY = the log and the code fit, but not proven.
- NOT VERIFIED = needs your answer or more logs.

## Your answers (2026-11-10)
1. Sign-up: "do what you think best" -> A + B as written, with A3 (nearby phones tell the server address).
2. 13:40-13:42: the app found the server **by itself**. So the same UDP search worked once the Wi-Fi was ready. This supports cause A1/A2 (one try while Wi-Fi was not ready), and B (nothing published it for 2 more minutes).
3. Add friend: the **Nearby list was empty / slow** -> E6-E9 added below.
4. Crown: about 18 % smaller; map crown unchanged.
5. Next: mock first. Done: `mocks/mock_256_signup_nearby_crown.jpg` (parts `mocks/mock_256_part1..5.jpg`).

---

## 0. What happened on the TECNO (timeline, plain words)

| Time | What the log shows |
|---|---|
| 13:35:35 | First open after install. Database 4.4 s, screen froze 2.5 s (`MAIN_STALL`), phone low on memory (`MEMORY_TRIM running_critical`). |
| 13:35:40 | Wi-Fi is connected but Android says **no internet yet** (`NET_START wifi=true internet=false`). |
| 13:35:42-56 | You typed the name and password and tapped Create (`KDF`). |
| 13:35:56 | The app searched for the server ONCE (one UDP ask, 3 s), found nothing, and **silently made an offline account** (@ibrahim). No log line says it searched or why it failed. |
| 13:36:02 | The C71 and Note are reached over the SAME Wi-Fi (LAN) at once. They know the server address, but the TECNO is never told. |
| 13:36:05 | Offline account check: `No LinkUp server is available on the local network` -> `NEXT_TRY in=next_connect`. |
| 13:36:26-34 | Add Contact search (server off): "nosh..." found through C71 (`FRIEND_SEARCH shown=1 asked=1`). Not added. |
| 13:36:42 | Wi-Fi dropped (`NET_CHANGE wifi=false`). |
| 13:37:35-46 | App left and came back (you were probably in Wi-Fi settings). |
| 13:37:52 | Wi-Fi back **with internet** (`internet=true`). **No retry of the account.** |
| 13:37:57 | Add friend from the Nearby list -> C71 (sajjad): done in 0.5 s, chat opened, Hello sent. |
| 13:40:00 | Call to C71, ended by you after 4 s. |
| 13:40:12 | App swiped away, background engine ran, reopened at 13:40:16 (fast, 0.96 s). |
| 13:40:31 | Account page shows "Can't reach LinkUp. Showing saved profile." for a phone that has no server yet. |
| 13:40:47 | The server was found and its key pinned (`PAIR_PROOF result=pinned`). You said it found the server by itself. |
| 13:42:31-47 | Profile save -> `PUT /api/v1/profile` **400** (2 times). |
| 13:42:47-56 | Home re-checked -> server OK -> "@ibrahim" already exists on the server -> same password -> **linked** to the old @ibrahim (`OFFLINE_ACCOUNT_DONE linked`, `ID_MOVED 8cd082->b71c0e`). |
| 13:42:51-57 | `PUT /api/v1/profile` **400** 2 more times (the saved profile change keeps failing). |
| 13:43:17 | HTTPS on (`TLS_243 on`), but the socket stays `ws://` (same as TODO_255 D1). |

**Result:** the server was on the same Wi-Fi the whole time. The account still went to the server only after **about 7 minutes and several manual steps**.

---

## A. Sign-up makes an offline account although the server is on (P0, CONFIRMED)

### Causes found in the code
1. **One weak search.** `DiscoveryService.discover` (`lib/features/connectivity/data/services/discovery_service.dart`) sends ONE UDP packet to `255.255.255.255:45454` and waits 3 s.
   - No second try. A single lost packet = "no server".
   - It is not tied to the Wi-Fi network. While Android says "Wi-Fi has no internet" (13:35:40), the packet can go out the wrong way or fail (LIKELY).
   - A socket error returns an empty list with **no log** (Bundle 201 E1).
2. **Silent fallback.** `AuthenticationBloc.submit` (`authentication_bloc.dart:97-122`): any `StateError` from `prepareForAuthentication` = offline account.
   - That includes "server identity changed" and a bad server proof (231), not only "no server".
   - The user is never told that the account is phone-only.
3. **No log of the decision.** There is no `AUTH_*` line for "searched / found / made offline because …". This log could only be read from side effects.
4. **Nearby phones are not asked.** The C71 and Note were linked over the same LAN 6 s after sign-up and both know `192.168.18.27:8080` plus the pinned key. The new phone never asks them.
5. **The Wi-Fi state is not used.** Sign-up does not wait when Wi-Fi is connected but not ready yet (`internet=false`). LinkUp needs the LAN, not the internet.

### Fixes (my advice)
- [x] **A1. Real server search** (sign-up, sign-in, offline publish, recovery all use the same one):
  - Ask 3 times (0 s, 1 s, 2.5 s), and wait up to 5 s in total.
  - Send to `255.255.255.255` AND to the Wi-Fi subnet broadcast (for example `192.168.18.255`), from the Wi-Fi address.
  - Stop as soon as one server answers.
  - Also try the saved server, and an address told by a nearby phone (A3).
  - Logs: `SERVER_SEARCH start`, `try n`, `found addr`, `none reason=no_wifi|wifi_not_ready|socket_error|no_answer`.
- [x] **A2. Wait for Wi-Fi.** If Wi-Fi is connected but not ready, wait up to 5 s before searching. Wi-Fi off = search skipped, and the log says so.
- [x] **A3. Nearby phones tell the server address.** The LAN/Wi-Fi Direct hello already goes between phones. Add `server address + key tail` to it.
  - A new phone with no server tries that address.
  - The server's own proof (231) is still checked and pinned exactly as now.
  - This is the same trust level as the UDP search today: any device on the LAN can answer that too.
- [x] **A4. Sign-up screen says what happens.**
  - While searching: "Looking for the LinkUp server…" with a small spinner, under the Create button.
  - Server found: normal server account (as now).
  - No server: still make the offline account (as you want), then show once a box "Saved on this phone": "No LinkUp server answered on this Wi-Fi. Your account is saved on this phone and goes up to the server by itself when the server is found." [OK] (mock 1).
- [x] **A5. Offline only when there is no server.** A server that answers with a problem shows the real message, and no phone-only account is made:
  - identity changed;
  - bad proof;
  - 235 "this phone has another account".
- [x] **A6. Log line** `AUTH_RESULT mode=server|offline reason=…` for every Create and Sign in.

Tests:
- [x] Search tries 3 times.
- [x] Subnet broadcast is sent.
- [x] Stops on the first answer.
- [x] Wi-Fi off = no wait.
- [x] The bloc goes offline only for "none found".
- [x] A nearby hint gets probed.
- [x] Old tests on discovery and auth fallback stay. I will list any that need a setup change.

---

## B. The offline account went up only after 7 minutes (P1, CONFIRMED)

`OfflineAccountSyncService.autoPublish` runs only:
- once at Home start (`from=home`);
- from the banner button;
- when the socket connects (`from=reconnect`, but that needs a server address first);
- in the background engine (app closed).

With the app open and no server address saved, **nothing retries**:
- not when Wi-Fi comes back (13:37:52);
- not when the server address gets saved (13:40:47).

`NEXT_TRY in=next_connect` never happens for a phone that has no server.

- [x] **B1.** While the app is open, try again when:
  - Wi-Fi comes up or becomes ready (`NET_CHANGE`);
  - the app comes back to the front;
  - every 60 s for the first 10 min, then every 5 min.
- [x] **B2.** Try at once when a server address is saved (any screen) or told by a nearby phone (A3).
- [x] **B3.** `NEXT_TRY` logs the real next time (for example `in=60s why=timer|wifi_up|server_saved`).
- Goal: on this log, the account would have gone up at 13:37:53 (Wi-Fi back) or at 13:36:03 (C71 told the address), not 13:42:56.

Tests:
- [x] A Wi-Fi-up event triggers a try.
- [x] Saving a server triggers a try.
- [x] The timer backs off.
- [x] No double run (the lock already exists).

---

## C. Account page shows "Can't reach LinkUp" for a phone-only account (P2, CONFIRMED)

- The Account page loads the profile from the server with an empty address, which gives `FormatException: Server address is required`.
- The screen shows the grey box "Can't reach LinkUp. Showing saved profile." (`account_center_screen.dart:268`), although there is no server to reach yet.
- The log line `ACCOUNT_OFFLINE_BOX` keeps the hidden error text ("The server returned a reply the app could not understand.", from `cleanBlocError`), which is only in the log, not on the screen.

- [x] **C1.** Phone-only account (no server address): box text "Your account is on this phone only. It goes up to the server by itself when the server is found." plus a **Find server now** button (runs A1 + B2).
- [x] **C2.** No server call at all when there is no address (also `ADMIN_ACT_SYNC_SKIP FormatException` at 13:36:08 and 13:40:22).

---

## D. Profile save fails with 400, again and again (P1, CONFIRMED that it fails; the field is NOT VERIFIED)

- `PUT /api/v1/profile -> 400 (44 bytes)` 4 times (13:42:32, :47, :51, :57).
- The server answer is 44 bytes, which fits exactly one of three 20-letter errors:
  - "invalid phone number";
  - "invalid display name";
  - "invalid request body".
- The app does not log the server's words.
- The saved profile change (`syncPendingProfile`) is sent again on every sync and never cleared, because the server keeps saying 400.
- My guess: the phone number field. The server accepts only `03xxxxxxxxx`, `923xxxxxxxxx`, `00…` or `+…` with 8-15 digits.

- [x] **D1.** Check the phone number in the app with the SAME rule as the server, before Save, with a clear message under the field ("Use 03xx xxxxxxx or +92…").
- [x] **D2.** `HTTP_ERROR_RESPONSE` logs the server's error text (short, no personal data).
- [x] **D3.** A 400 for a saved profile change:
  - stop resending it;
  - keep the rest of the profile;
  - show once: "Your phone number was not saved: <reason>".
- [ ] You: tell me what you typed in Profile (question 3).

---

## E. Add friend flow (P1)

**Seen:**
- Search with no server found noshad through C71 (`FRIEND_SEARCH shown=1 asked=1`), but he was never added. There is no `FRIEND_ADD_TAP source=online`.
  - Either the result was not tapped, or the tap failed with no log. NOT VERIFIED (question 4).
- Wi-Fi dropped right after the search (13:36:42) and came back at 13:37:52. During that time Nearby showed nobody.
- Add from the Nearby list worked fast: tap -> accept in 0.3 s -> chat open -> Hello -> reply.
- `CONTACT_PUSH_DEFERRED` at 13:37:58 (no server yet). After the account went up, there is no log line that the contact was pushed (NOT VERIFIED).
- After the account went up, the C71 still sends to the OLD offline id: `CONTACT_EDGE_FORWARDED to=8cd082` at 13:44:04, while the new id is `b71c0e`. The friend did not learn the new id (LIKELY).
- noshad became a contact only through the server at 13:42:50 (`relay link upgraded to contact`).

**Fixes (my advice):**
- [x] **E1.** A search result found through a friend's phone gets an **Add** button that works with no server. It uses the signed public card the friend sent (233), the same as Nearby add. Log `FRIEND_ADD_TAP source=friend_card` and `FRIEND_ADD_FAIL reason=…`.
- [x] **E2.** Every add failure is logged and shown in plain words (today the `_addFromResults` errors have no log).
- [x] **E3.** Top of Add Contact: one small status line:
  - "Server connected";
  - "No server - searching nearby phones";
  - "Wi-Fi off - using Wi-Fi Direct".
  - Tap it -> Find server now (A1).
- [x] **E4.** After the offline account goes up:
  - push the contacts that were waiting (`syncServerContacts` right after the join);
  - log `CONTACT_PUSH ok n=…`.
- [x] **E5.** After `ID_MOVED`, tell friends the new id (signed "my id moved" note over LAN/WD + server), so they stop using the old offline id.
- [x] **E6. Nearby status line** under the "Nearby" title, with three small chips: Wi-Fi on/off, Wi-Fi Direct on, Bluetooth allowed/not allowed. You can see at once why the list is empty (mock 3).
- [x] **E7. Wi-Fi card** when Wi-Fi goes off or the phone leaves the Wi-Fi: "Wi-Fi went off. Phones on your Wi-Fi can't see you. Still looking with Wi-Fi Direct." with a **Wi-Fi** button. The button only opens Android Wi-Fi settings; nothing is changed by itself.
  - On the TECNO, Wi-Fi went off at 13:36:42 just after Android said "no internet" (LIKELY the phone's own "switch away from Wi-Fi without internet").
- [x] **E8. Keep just-seen phones 2 min.** Today a phone leaves the list 20 s after the link drops (`PRESENCE_CHANGED Nearby>Offline why=expiry` at 13:37:00). After: it stays greyed with "Seen 40 s ago" and **Add friend** still works (it tries Wi-Fi Direct / Bluetooth).
- [x] **E9. Bluetooth card stays on top while the list is empty** (TECNO never allowed Bluetooth: `BLE_STATE no_permission` the whole time). The permission is still asked only from the Allow card.
- Log `NEARBY_LIST shown=n lan=n wd=n ble=n kept=n why_empty=wifi_off|no_perm|none` every 30 s while Add Contact is open, so the next log shows what you saw.


---

## F. Crown a little smaller, whole app (P2, CONFIRMED where it is set)

One formula sizes the crown everywhere: `AdminCrown.sizeFor(radius) = max(13, 1.1 x radius)` (`lib/core/widgets/admin_crown.dart:168`).

- [x] **F1.** New size: `max(11, 0.9 x radius)` = about 18 % smaller (my advice).
  - Photo radius 24 (lists): 26.4 -> 21.6.
  - Radius 40 (profile): 44 -> 36.
- [x] **F2.** The room above the photo (`AdminCrown.room`, `AdminCrownRoom`) follows by itself, so nothing gets cut.
- [x] **F3.** Fixed crowns:
  - account switch sheet 24 -> 20;
  - admin chats / actions / panel 18 -> 15.
- [x] **F4.** The gold ring round the photo stays as it is.
- [x] **F5.** The network map crown (`link_paths_map.dart` lines 958/970, sizes 12 and 18) sits inside the 222 locked part ("don't change animated line"). Two choices:
  - leave it as it is (my advice);
  - or you allow updating the lock test.
- Old tests that change (numbers only):
  - `bundle217d_test.dart:10-11`;
  - `bundle216a_test.dart:27-28`;
  - `bundle214d_test.dart:60-61`.
- [x] Mock: `mocks/mock_256_part4.jpg` (chat header, People, Chats, Profile; now vs after).

---

## G. Other lines in the log

- OK, working as planned:
  - `ADMIN_BADGE_REJECT no_trust` (12x) and `ADMIN_BLOCK_REJECT no_trust` (20x): a new phone does not trust admin cards before it reaches the server once (your security rule). They stopped after the server join (`ADMIN_ACT_TRUST_RECHECK`).
  - Small fix: log once per minute instead of every time (P3).
- OK: `ADMIN_ACT_WAIT_TRUST` then `ADMIN_ACT_NOT_MINE` after trust (254 works).
- OK: `LINK_AUTH legacy reason=no_local_key` on a brand-new phone, until the link key arrives.
- OK: reopen after a swipe-away took 0.96 s; the background engine took over while closed.
- OK: same name + same password linked to the old @ibrahim (218/235 path).
- Known: `TLS_243 on` but the socket stays `ws://` until it reconnects (TODO_255 D1).
- Slow first open on this phone: database 4.4 s, freeze 2.5 s, low memory. P3; watch it on the next logs.
- `WD_TAG_FAIL step=discover reason=2` (Wi-Fi Direct busy) once: harmless.
- System lines (`mali_gralloc R8`, `unisoc vdex`, `OnBackInvokedCallback`): phone system messages, not LinkUp.

---

## H. Order, tests, delivery (when you say go)

1. A1 + A2 + A6 (search + logs)
2. A4 + A5 (screen text, offline only when no server)
3. B1-B3 (fast publish)
4. A3 (nearby phones tell the server address)
5. C, D, E2-E5
6. E1, E3, E6-E9 (Nearby)
7. F (crown)

- One app zip, one commit (3.0.74, together with TODO_255 if you want). No backend change.
- Full app test suite before the zip. I will list any old test that changes (F numbers; maybe the auth fallback setup).
- Phone test after:
  - fresh install on the TECNO with the server on -> server account at once (no offline);
  - server PC off -> offline account plus the note -> server on -> goes up within 60 s by itself.

## Questions for you (ANSWERED 2026-11-10, see "Your answers" at the top)
1. Should the TECNO sign-up give a server account when the server is on, and an offline account only when no server answers in about 5 s? (my advice: yes)
2. At 13:40-13:42, what did you do? Did you type the server address, scan a QR, or did it find the server by itself?
3. What did you type in Profile (name / phone number)? It was refused 4 times.
4. Add friend: what was not smooth? The search result not adding, Wi-Fi dropping, or too many steps?
5. Crown size: about 18 % smaller (my advice), or about 30 % smaller? Map crown: leave it (my advice)?

---

## Build notes (3.0.74+145, 2026-11-10)
- A1/A2: `DiscoveryService` asks 3 times (0 / 1 / 2.5 s, 5 s total), to `255.255.255.255` and the /24 subnet broadcast, from any address and from each Wi-Fi address. Log `SERVER_SEARCH start|try|found|none reason=no_wifi|wifi_not_ready|socket_error|no_answer`. Default timeout 5 s (the Wi-Fi scan button keeps 3 s).
- A3: built as its own small message `server_hint_256` (address + last 8 letters of the pinned key), sent by a phone that reached the server when a phone links to it (once per 10 min per phone). The new phone only TRIES it: the server proof (231) is checked as usual and a wrong key tail is skipped. Old apps ignore the message.
  - Limit: before the first sign-up there are no phone links yet (they start after the account exists), so A3 helps the "goes up by itself" part (B), not the first Create. The first Create relies on A1/A2.
- A4: "Looking for the LinkUp server..." / "Server found" lines under the button; dialog "Saved on this phone" after a phone-only Create.
- A5: identity changed / bad proof = `ServerProblem256`, message shown, no phone-only account.
- A6: `AUTH_RESULT what=create|sign_in mode=server|offline|none reason=...`.
- B: `OfflinePublishTicker256` (Home): every 60 s for 10 min, then every 5 min; also on Wi-Fi up, app resume, new server address saved, server hint. `NEXT_TRY in=60s why=timer`.
- C1/C2: phone-only box + Find server now; Account page makes no server call while the account is phone-only. `ADMIN_ACT_SYNC_SKIP` left as it is (log line only).
- D1: same phone rule as the server (`normalizePhoneNumber`); Save stays off with the hint. D2: `HTTP_ERROR_RESPONSE ... error="invalid phone number"`. D3: a 400 for the saved change stops the resend (bad number dropped, rest sent once), note shown once on Profile.
- E1/E2: search results from friends already add with no server (saved signed card); now `FRIEND_ADD_START source=online|friend_card` and `FRIEND_ADD_FAIL source=... reason=...`, plain failure words.
- E3: status line at the top of Add Contact (tap = Find server now).
- E4: `CONTACT_PUSH ok n=...`. E5: after the join, my new card goes straight to every friend (`ID_MOVED_TELL`); their phones move the old offline id (218c rule: same phone + same key).
- E6-E9: chips, Wi-Fi card (opens Android Wi-Fi panel only), kept 2 min greyed with "Seen 40 s ago" + Add friend, Bluetooth Allow card ignores the 7-day hide while nobody is listed. `NEARBY_LIST` every 30 s.
