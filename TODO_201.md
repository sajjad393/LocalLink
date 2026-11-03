# TODO 201: issues from the 04 Nov test + connection words (mock ST)

Base: git code (199b `e2488b9`) + bundle 200 only. No group code (groups stay parked).
Freeze is ON. Nothing below is built until you say "Go ahead 201".
Version when built: **3.0.38+109**. The unpushed group zips already used 3.0.36 and 3.0.37, so 201 skips those numbers.

Test: Realme = Sajjad (`…da19f3`), ZTE = Sumaira (`…16a834`). Both on 3.0.35+106, no server set (`serverConfigured=false`).

## Decisions so far (your answers)
- Look: **"same like mock"**. The words, info card, People line and call chip are exactly as mock ST S1–S5. Photo badge = **like S6–S7: a new badge per way** (Wi-Fi icon, two phones, purple mesh dots, globe, orange dot, grey dot). You chose this over the old bundle 153 "badge must not change" rule.
- "Connecting…": **same like mock**, so it's shown (orange dot, during the 20 s grace).
- A5 remember the friend's Wi-Fi Direct address 24 h + 5 s wait in "deaf" mode: **Yes**.
- Build: **one bundle 201** (A–F), one zip, one commit.
- Still frozen until "Go ahead 201".

---

## 0. What really happened (short timeline from both logs)

| Time | What happened |
|---|---|
| 01:14:03 | Sumaira (ZTE) added Sajjad from the Nearby list. Hello, messages and a call all worked over the router. |
| 01:15:31 | Wi-Fi off on both. Every LAN send now fails (`ENETUNREACH`). |
| 01:15:45 – 01:16:38 | The app was opened and closed **4 times on Realme** and 2 times on ZTE (`NEARBY_BG_STATE close / bg_start / open`). |
| 01:16:17 | ZTE (smaller id) opened the friend backup link `DIRECT-LL-AKkeR6`. |
| 01:16:47 | ZTE's link closed by itself after 30 s with nobody joined (`WD_FRIEND_CLOSE reason=link_lost was=host`). The logs don't say why. |
| 01:16:55 | ZTE opened it again. |
| 01:17:01 | You tapped "Add" on the Realme Nearby list (`PAIR_UI pair_button peer=ZTE Blade A35`). |
| 01:17:03 | Realme joined by itself: `WD_SIGN none after_s=21` and then `WD_FRIEND plan=join reason=friend_group_seen`. Its 20 s wait timer had just ended. **The "Add" tap didn't cause the join; the timing was luck.** |
| 01:17:04 – 01:17:06 | The stuck messages from both sides went through within 1–3 s. |
| 01:18:22 | A call over Wi-Fi Direct worked. The calls at 01:16:04 and 01:16:47 failed because there was no link yet. |
| 01:19:40 | Wi-Fi came back. The backup link closed (`router_back`) and the router took over. |

Stuck time ≈ **1 min 35 s**. Bundle 200's target was under 1 minute.

**Correction to my earlier reply:** I said "status still said Nearby during the gap". The log can't show that: the 5 s presence timer flips a person to Offline **without writing a log line** (`presence_hub.dart` `checkExpiry()` l.327). Issue E below adds that log line so we can know next time.

---

## A. Friend backup link (Wi-Fi Direct) is too slow: 1.5 min instead of under 1 min

### A1. The 20 s wait starts again every time the app is opened or closed (main cause)
- **Proof:** Realme's `WD_SIGN after_s=21` at 01:17:03 means its clock only started at 01:16:42, 4 s after the last app open (01:16:38). ZTE: opened at 01:15:53, sign at 01:16:17 (22 s). Wi-Fi had been off since 01:15:31.
- **Why:** when the app opens or closes, Nearby switches between the app and the background engine. The "friend missing since" times live only in memory: `wifi_direct_fallback_service.dart` l.263 `_friendWantedSince`. So each switch starts the 20 s wait from zero. People open the app exactly when messages are stuck, so this hits every time.
- **Fix:** save "friend missing since" per friend in a small setting and read it back on start. Keep it at most 10 minutes. Clear it the moment the friend is reachable again (same rules as today).
- **Why safe:** only the start time is kept; no rule changes. Old or unknown values are ignored after 10 min.
- **Test:** unit test with the time restored after a "restart", where the plan acts at once if 20 s already passed.

### A2. The friend's hidden "sign" is never heard on these phones
- **Proof:** every search window on both phones ended with `heard=0`: 24 on Realme and 23 on ZTE. Bundle 200 waits 20 s for that sign before doing anything else, so on these phones that wait is always wasted.
- **Why (likely, not proven):** both phones use a Unisoc chip. The Wi-Fi Direct "service search" Android offers is known to be unreliable. Also, our search starts the "publish my sign" and the "search" steps at the same moment on the same channel (`NearbyTagManager.kt` `discover()` l.296: `publish()` and `startRequest()` together). Some phones drop the search when that happens.
- **Fix, 3 small parts:**
  1. **Order:** run the search only after publishing has finished (chain it on success or failure, as `publish()` already does with clear and add).
  2. **"Deaf" mode:** if the last 3 windows heard nothing while LinkUp phones were around, the 20 s wait becomes 5 s (`FriendLinkRules.signWaitMs`, `nearby_friend_link.dart` l.123). One good window switches back to 20 s.
  3. **Diagnosis:** log the first raw answer of each window (today the answer listener is empty: `{ _, _, _ -> }` l.311). One line per window: `WD_TAG raw=…`.
- **Why safe:** the search, the window length and the battery rules stay the same. Only the waiting time changes, and only on phones that can't hear signs anyway.

### A3. ZTE's first backup link died after 30 s and the reopen waited
- **Proof:** opened 01:16:17, gone 01:16:47 (`group state role=none`, not closed by us). After that, `WD_PEERS n=0` gave `plan=none reason=no_phone_seen`, so the reopen waited until 01:16:55.
- **Fix:**
  1. Log why Android dropped it (the group-removed event details, one line `WD_GROUP_LOST …`).
  2. When our friend link dies by itself and the friend is still missing, count a phone seen in the last 60 s as "seen". Don't wait for the peer list to fill up again.
- **Why safe:** the reopen keeps the existing backoff and battery rules (`_backoff.mayAct`, battery ≤10%, rest after idle closes).

### A4. Realme saw ZTE's open link 25 s late
- **Proof:** ZTE was hosting from 01:16:17. Realme's peer list only showed it as host (`ZTE Blade A35/3/go`) at 01:16:42. Realme had a search window from 01:16:13 to 01:16:33 and the list didn't change.
- **Fix:** ask Android for a fresh peer list at the start of each window and again 10 s later (`requestPeers`), so the "host" flag is never old.
- **Why safe:** read-only. It doesn't start any new search.

### A5. Faster join to a known friend phone (needs your OK, question 3)
- When the friend link worked once, remember the friend's Wi-Fi Direct address for 24 h. Here that was `ca:cb:14:d8:f3:7d` (`WD_FRIEND_JOIN host=…`).
- If that address shows up as a host and the friend is missing, join at once (no 20 s wait).
- A wrong guess is harmless: the join uses the pair password, so it simply fails and that address is skipped for 5 min (existing rule).
- Android can change this address after a restart or a Wi-Fi switch. It's only a shortcut; the normal rules still work without it.

**Expected result of A1–A5:** about 25–40 s from Wi-Fi off to messages flowing, instead of 95 s.

---

## B. The Wi-Fi Direct link drops and reconnects every 5 seconds (found in the logs)
- **Proof:** from 01:17:03 to 01:20:46, Realme reconnected about **40 times**: `LINK_AUTH verified side=dial`, then right after `transport_link_died … cause=eof`, then `peer_connected`. ZTE shows the same with `read_exception`. It also caused a lot of `full map asked reason=missed_update`. Messages still got through, but each drop can lose a moment of a call and wastes battery.
- **Root cause (code):**
  - `LocalLinkTransportService.kt` l.1462 stores a Wi-Fi Direct link with **no host address** (`ownerAddress = null`).
  - The checks "am I already connected to the host?" look only at that address (l.1366 in `connectTransportToOwner`, l.4064 in the 5 s maintenance loop).
  - So they always answer "no", and the phone dials the host again every loop. The new link then replaces the old one.
- **Fix:** in those two checks, also count a Wi-Fi Direct link whose remote address equals the host address (`it.remoteAddress == owner`).
  - Don't change `ownerAddress` itself. Other code uses `null` to mean "the other side is the host" (l.1634, l.4227).
- **Why safe:** a two-line change in two checks. It only stops extra dials when a working link already exists. If the link really dies, the check sees a closed socket and dials as before.
- **Test:** Kotlin unit test of the new "already linked" helper. Phone test: no `transport_link_died` while the backup link is up.

---

## C. Call icon missing when a chat is opened from a notification
- **What you saw:** on the phone that got the message, the call icon wasn't in the chat top bar. After reopening the app it was there.
- **Root cause (code):** the chat screen shows the call icon only when it gets a "start call" action (`chat_screen.dart` l.971 `if (widget.onStartCall != null …)`; the same check controls "Voice call" in the info sheet, l.728). Two ways of opening a chat don't pass that action:
  1. tapping a message notification: `local_link_app.dart` `_openNotificationTarget` l.369 → the `ChatScreen(...)` at ~l.393;
  2. the chat that opens by itself after adding a friend: `_openFriendChat` l.124 → `ChatScreen(...)` at ~l.149.

  Opening from the Chats list goes through `home_screen.dart` `_chatRoute` l.816, which passes it, so the icon shows there.
- **Fix:** one shared "start call from a chat" helper in `local_link_app.dart`, doing exactly what Home does:
  - a live call is resumed instead of starting a new one;
  - otherwise start the voice call and open the call screen.

  Pass it, plus `calls`, in both places.
- **Why safe:** the chat screen already handles it; the blocked rules (no icon when blocked) stay inside the chat screen. Video stays paused.
- **Test:** widget test: chat opened via the notification path shows the `Call` button and the "Voice call" sheet row.

---

## D. Already-added friend shows in the Nearby list (your question)
- **Why it happens:** with the router, your friend is hidden because the app knows them by their LinkUp id. With Wi-Fi off, the friend's phone is only seen as a **Wi-Fi Direct name** ("ZTE Blade A35"). The app can only match that name to a person through the hidden sign (A2), and on these phones the sign never arrives. So the phone looks like a new person and gets an Add button. That's exactly the card you tapped at 01:17:01. The rule is in `nearby_list_plan.dart` l.129: a phone without a sign is shown when no friend nearby can explain it.
- **Fix (two small rules):**
  1. Use the remembered friend Wi-Fi Direct address from A5 (24 h). If it matches, hide the card.
  2. A friend who was Nearby in the last 10 minutes and is now missing also "explains" one unknown Wi-Fi Direct phone. The card stays hidden while the backup link is being made.
- **Why safe:** a real new person still shows:
  - when they carry a sign;
  - when there are more unknown phones than missing friends;
  - after 10 minutes.

  A QR code always works.
- **Also:** tapping Add on your own friend's card did no harm (no second friend and no message mix-up). After D, that card simply isn't there.

---

## E. Small items
1. **Crash-type log on open with Wi-Fi off:** `uncaught_async_error SocketException: Network is unreachable` comes from the server search broadcast (`discovery_service.dart` l.44, `socket.send` without a catch). Fix: catch it, return "no server found" and log one line. No visible change.
2. **Presence log:** log `PRESENCE_CHANGED` also when the 5 s timer flips someone (`checkExpiry`), so a log can show exactly when Nearby became Offline.

---

## F. Connection words (mock ST, approved look)

### What changes on screen (mock ST, S1–S7)
- **Chat top bar:** "Nearby · Wi-Fi", "Nearby · Wi-Fi Direct", "Nearby · Mesh, via 1 phone", "Online", "Offline" (+ "Connecting…" if you want it). Small coloured icon before the words.
- **Info sheet** (tap the name): same words, plus the card "Connected by …" with one plain sentence.
- **People:** a status line under @username.
- **Call screen:** a chip under the timer: "Wi-Fi call" / "Wi-Fi Direct call" / "Mesh call" / "Online call". It updates if the call switches way.
- **Chats list hold-sheet subtitle** (`home_screen.dart` l.783): same words.
- **Photo badge (S6–S7, chosen):** `PresenceAvatar` badge in `messenger_conversation_tile.dart` l.247–257 gets one icon and colour per way. Same size and place as today (top-right). It appears everywhere that badge is used: Chats list, chat top bar, People, Calls tab, info sheet. The "Blocked" grey look stays as it is.
- **Not changed:** the All / Nearby / Online filters; who counts as Nearby; message sending.

### Where the "way" comes from (already in the code)
- `LocalRouteResult.kind` = `lan` / `wifiDirect` / `mesh` / `none`, with `hopCount` (`local_route_policy_service.dart` l.104–140). LAN already wins over Wi-Fi Direct, and Wi-Fi Direct wins over mesh.
- `lan` → "Wi-Fi". `wifiDirect` → "Wi-Fi Direct". `local_net` (another phone's hotspot or group joined as Wi-Fi, bundle 161) → also "Wi-Fi Direct", since it's phone to phone. `mesh` → "Mesh, via N phones" (hops − 1, at least 1).
- Online = the same server proof as today.

### How it's built so nothing else breaks
- `PresenceHub` keeps the **same** `statusOf` / `labelOf` / `channelOf`. All filters, call rules and tests that use them stay exactly as they are. Only the badge drawing reads the new way (S6–S7).
- New `PresenceHub.wayOf(id)` and `wayLabelOf(id)` are used **only** by the 5 text spots above.
- `attach()` gets an extra optional input with the route kind and hops. The old `localPaths` input stays, so the 5 test fakes keep working.
- "Connecting…" (if approved) only replaces the **text** during the existing 20 s grace (`pathGrace`, l.73). The status stays "Nearby" for logic, exactly as today.
- Tests: unit tests for `wayOf` (each kind, hops, LAN wins, grace gives Connecting, server-only gives Online). Widget tests for the top bar, People row and call chip. Existing label tests stay unchanged.

---

## G. Phone tests after building (both phones, same as this test)
1. **On the router:** chat top bar says "Nearby · Wi-Fi". People shows the same. A call shows a "Wi-Fi call" chip.
2. **Wi-Fi off on both, app closed:** send from both. Messages arrive within about 40 s. The top bar goes "Connecting…" → "Nearby · Wi-Fi Direct".
3. Same as 2, but open and close the app 3 times while waiting. It must not get slower (A1).
4. **On the backup link for 3 min:** no `transport_link_died` in the logs (B). A call works.
5. Tap a message notification. The chat opens with the call icon (C).
6. Open Add friend → Nearby with Wi-Fi off. The friend isn't listed (D).
7. **Wi-Fi back:** "Nearby · Wi-Fi" within about 1 min. The backup link closes.
8. Send logs from both phones (look for `WD_SIGN`, `WD_TAG raw`, `WD_GROUP_LOST`, `PRESENCE_CHANGED`).

## H. Files that change (expected)
- `lib/app/local_link_app.dart` (C, F attach)
- `lib/core/presence/presence_hub.dart` (E2, F)
- `lib/features/connectivity/data/services/wifi_direct_fallback_service.dart` (A1, A3, A5)
- `lib/features/connectivity/data/services/nearby_friend_link.dart` (A2, A5 rules)
- `lib/features/directory/presentation/nearby_list_plan.dart` + `nearby_people_section.dart` (D)
- `lib/features/connectivity/data/services/discovery_service.dart` (E1)
- `lib/features/messaging/presentation/screens/chat_screen.dart` (F top bar + sheet)
- `lib/features/directory/presentation/contacts_screen.dart` (F People line)
- `lib/features/home/presentation/screens/home_screen.dart` (F sheet subtitle)
- call screen header widget (F chip)
- `android/.../NearbyTagManager.kt` (A2 order + log), `NearbyRadio.kt` (A4), `LocalLinkTransportService.kt` (B, A3 log)
- new tests: `bundle201_*_test.dart`, Kotlin policy tests.

Not touched: groups, the 1:1 chat composer, call audio, the server.
