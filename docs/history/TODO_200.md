# TODO 200: phones talk without the router

Status: **PLAN ONLY. Decisions done (§8).** The freeze is on, so nothing gets built until you say "Go ahead 200".
Base: **the latest git code only**, LocalLink `e2488b9` (199b, 3.0.34+105). I checked GitHub on 3 Nov: nothing newer.
New version: **3.0.35+106**.
**No group changes (G1–G4) are included.** Their files stay parked in the workspace until you say so.
200 is built in a fresh copy of the git code, never in a group work folder.

---

## 0. What the logs showed (3 Nov, 20:48–21:48, both phones on 3.0.32+103)

1. 21:00:49: the router went off on both phones (`NET_CHANGE wifi=false`).
2. 21:43–21:48: 4 messages stayed in the outbox (`route=none`), and 4 calls ended up
   `CALL_INVITE_SENT transport=none queued=true`.
3. Each phone **could see** the other. At 21:45:09 you tapped "realme C71" on the ZTE.
4. Neither phone ever heard the other's hidden LinkUp sign (the "tag"): `tag found` = 0.
   Each phone searched about 50 times in 5 minutes.
5. Without the sign, the app never connects (`group plan=none reason=idle tags=0`,
   `pair_wait_tag` → 60 s → nothing). Since bundle 177 there is no "Connect?" pop-up,
   so nothing else was tried.
6. I checked all 15 log files from 1–3 Nov (3.0.14 to 3.0.32). The sign was **never** found,
   not once. So this is an old problem; it only shows when the router is off.
7. The code checked out: the tag search is started from 3 places, and every start cancels
   the search that is still running:
   - the Dart group timer (`_groupTick` → `_groupDiscovery` → `discoverPeers`: every 8 s urgent,
     15 s foreground, 60 s / 3 min background);
   - native `discoverPeers` success → `tags.scheduleDiscovery()` 1.5 s later;
   - native `onPeersChanged()` (at most once per 8 s, but "peers changed" comes every 2–5 s).
   - Every start runs `clearServiceRequests` → `addServiceRequest` → `discoverServices`
     (`NearbyTagManager.discover()`), which throws away the search that was still running.
   - Together that is a restart about every 5 s. The answer from the other phone most likely
     never has time to arrive. This is a known Android problem: the sign search only works
     when both phones keep searching for phones and don't restart too fast.

---

## 1. What must be true after 200 (acceptance)

| # | Check |
|---|---|
| A1 | **Router ON: nothing changes.** Local Wi-Fi first stays (`lan_first`). The same speed as today. |
| A2 | Router OFF, both apps open: a message arrives in **≤ 30 s** (target; proven on the phones). |
| A3 | Router OFF: a call **rings in ≤ 30 s** and connects. Voice works the same as on Wi-Fi Direct today. |
| A4 | Router OFF, the receiver's app closed (service running): a message arrives in **≤ 2 min** (target). |
| A5 | **No pop-ups** (177 rule kept). Silent join with name + password only (Android 10+; both phones are 14/16). |
| A6 | Battery rules kept: app closed and ≤10% = no search; <20% = every 10 min; no search during a call (184/189). |
| A7 | The router comes back while connected: no cut during a call. Afterwards it goes back to router-first. |
| A8 | Transport stays invisible: the screens still say only Nearby / Online / Offline. |
| A9 | No new screens. The "Allow location all the time" card that already exists is reused (§8 Q3). **No mock needed.** |
| A10 | Every step writes a log line, so a failure shows exactly where it stopped. |

---

## 2. Part A: search the right way

Files: `android/.../NearbyTagManager.kt`, `android/.../NearbyRadio.kt`,
`lib/features/connectivity/data/services/wifi_direct_fallback_service.dart`,
`lib/features/connectivity/data/services/nearby_group_planner.dart` (`NearbySearchCadence`).

- [x] **A-1. One search window = 20 s.** `NearbyTagManager` keeps `windowUntil`. While a window is open:
  - no new `clearServiceRequests` / `discoverServices`;
  - `onPeersChanged()` does nothing (the running search already covers new phones);
  - `scheduleDiscovery()` does nothing.

  *As built:* no tap exception — a tap is served by the running window (at most 20 s). Simpler and it cannot cut a window. `onPeersChanged` starts a window at most every 25 s.
- [x] **A-2. Keep the phone "visible" during the window.** `discoverPeers` is called once at the start of
  the window and is **not** called again inside it. Android keeps peer discovery on for about 2 min, so the
  phone keeps answering the other phone's sign questions.
- [x] **A-3. Start order (unchanged, but logged):** `discoverPeers` OK → 1.5 s → service request → `discoverServices`.
  - On `BUSY (2)`: one retry after 3 s.
  - On `NO_SERVICE_REQUESTS (3)`: `stopPeerDiscovery` → `clearServiceRequests` → start again once (known Android bug).
- [x] **A-4. New cadence** (`NearbySearchCadence`): the time between window starts becomes
  - urgent (tap / call / host lost): **25 s** (was 8 s);
  - foreground with something waiting, or no Wi-Fi: **30 s** (was 15 s);
  - all other values stay: 60 s, 3 min, 10 min (<20%), stop (≤10%).

  Because each window lasts 20 s, the phone is searching most of the time when it matters.
- [x] **A-5. Random start offset 0–3 s** per window, so the two phones don't restart at exactly the same moment.
- [x] **A-6. Calls:** the existing pause stays (`CallNearbyPause`, 184/189). A window that is open when the call voice
  starts is stopped (`stopSearchForCall`, already there).
- [x] **A-7. The Dart timer stops starting searches itself while a native window is open.** `_groupDiscovery` asks
  native `searchWindowOpen` first, so there is one owner of the search instead of three.
  *As built:* native `discoverPeers` itself returns at once (does nothing) while a window runs, so the Dart timer needs no change.

---

## 3. Part B: friend link without the sign (the backup)

Idea: two friends already share a secret link key (bundle 160, `LinkKeyService`; native already has it,
`LINK_AUTH keys pushed contacts=1`). From that key, both phones make the **same private Wi-Fi Direct
name + password**. Only these two phones can make it, and it is different for every friend pair. One phone
opens that group and the other joins it silently, like a saved Wi-Fi. No sign is needed and there is no pop-up.

> **Changed while building (3 Nov):** the plan said "read the normal Wi-Fi list" (`getScanResults`). The code check
> showed the app's location permission stops at Android 12 (`maxSdkVersion=32`), and Android still needs location
> for that list on 13+. Both test phones are Android 14/16, so it would always be empty. **Built instead:** the
> Wi-Fi Direct peer list already says which nearby phone hosts a group (`go`), with no location permission. The
> joiner tries such a phone with the pair password; a wrong one fails after 25 s and is skipped. No new
> permission, no pop-up, no UI.

- [x] **B-1. Name + password** (Dart, `nearby_friend_link.dart`, unit-tested):
  - name = `DIRECT-LL-` + 6 letters from `HMAC-SHA256(linkKey, "wd-name-v1")` (same alphabet as `NearbyGroupPolicy`);
  - password = 16 letters from `HMAC-SHA256(linkKey, "wd-pass-v1")`;
  - both phones use the link key of their newest own key (entry 1 of the 3), so both get the same name.
- [x] **B-2. When the backup starts (all must be true):**
  1. not on router Wi-Fi that really connects phones;
  2. the friend is not reachable (no LAN, no group, no mesh route) and no fresh LinkUp tag of the friend was heard;
  3. it stays like that for one window (20 s) — `WD_SIGN none`. (Not tied to the 10-min waiting list, so Q2
     "stay connected" keeps working after the waiting list expires.)
  4. this phone is not a member of another group; a normal tag group is left alone;
  5. the normal tag rules did nothing this round (they still go first when tags work);
  6. battery: not at ≤10% with the app closed (same rule as the search);
  7. blocked people never get a backup link; at most 2 friends at once (Q4).
- [x] **B-3. Who opens, who joins:** the smaller id opens — only when some phone without a tag is seen in the
  Wi-Fi Direct list (it may be the friend; no group for nobody). The bigger id joins. The bigger id opens itself
  only with a message waiting (or a call going) and no friend group for 30 s more.
- [x] **B-4. Open = new native `createFriendGroup(name, key)`** in `NearbyRadio.kt` (allowed with the app closed,
  like `createNearbyGroup`). The tag is published as for any group.
- [x] **B-5. Find = the Wi-Fi Direct peer list.** Native adds `go` (that phone hosts a group) to each peer.
  A host phone without a LinkUp tag → silent join with the pair name + password.
  - not a member after 25 s → `cancelConnect`, skip that phone for 5 min (30 min after 2 failures) — `WD_FRIEND_SKIP`.
- [x] **B-6. Join = existing `joinNearbyGroup(name, key)`** (silent password join, already used since 157). After the join the
  existing steps run: group IP link → `LINK_AUTH` hello with the link key → `peer_connected` → the outbox sends →
  waiting call invites go out.
- [x] **B-7. Both opened at the same time** (same name, both hosts): the bigger id leaves and joins the other
  one (native waits 1.5 s between). The smaller id stays.
- [x] **B-8. Closing:**
  - friend group with no member for **3 min** → close, then rest 2 min before opening again (10 min after 3 empty closes in a row);
  - a linked friend group stays (Q2); never closed or moved during a call;
  - the router is back: an empty friend group closes; a linked one stays (router path is used first anyway);
  - the friend link drops: no "new host" step for it (that step is for tag groups only).
- [x] **B-9. Failures:** the existing group back-off is reused for both open and join; a failed join skips that
  host phone (5 min, then 30 min).
- [x] **B-10. Tap in the Nearby list without a sign:** unchanged flow; the running 20 s window is not cut by the
  tap (no restart). A friend is linked by the backup anyway. No pop-up (177).
- [x] **B-11. One friend link at a time.** Wi-Fi Direct allows one group per phone. If several friends are waiting:
  first the friend with a call waiting, then the oldest waiting message.

---

## 4. Part C: logs (all one line, plain)

| Line | When |
|---|---|
| `WD_SEARCH start window=20s why=urgent/fg/bg peers=N` / `WD_SEARCH end heard=N linkup=N` | each window |
| `WD_PEERS n=2 list=realme C71/3/go,…` (name/status/go) | peers list changed (or once a minute) |
| `WD_TAG_FAIL step=peers/request/services reason=BUSY/ERROR/NO_REQUESTS` | any failure |
| `WD_SIGN none friend=1a2b3c4d after_s=20 peers=N` | 20 s without the friend's sign |
| `WD_FRIEND plan=… reason=…` | the backup's decision changed (smaller_opens, friend_group_seen, no_phone_seen, battery, …) |
| `WD_FRIEND_OPEN friend=… grp=DIRECT-LL-ab… reason=…` / `WD_FRIEND_OPEN hosting` / `failed` | backup opened |
| `WD_FRIEND_JOIN friend=… host=<addr> leave=0/1` / `WD_FRIEND_JOIN linked` | join |
| `WD_FRIEND_CLOSE reason=idle/router_back rest_s=…` / `reason=link_lost` | close |
| `WD_FRIEND_SKIP host=<addr> min=5/30 fails=N` | a join that did not form |
| existing `MESSAGE_ROUTE_SELECTED_DIRECT route=…` and `CALL_INVITE_SENT transport=…` | the message / call used the friend link |

The `LinkUp-logs` export gets these under area NEARBY. No secret (key, password) is ever logged; only the first 4 letters of the name.

---

## 5. Files (code-checked on `e2488b9`)

| File | Change |
|---|---|
| `android/.../NearbyTagManager.kt` | search window (A-1…A-5), `WD_SEARCH` / `WD_TAG_FAIL` / `WD_SIGN` logs |
| `android/.../NearbyRadio.kt` | `discoverPeers` skipped while a window runs, `createFriendGroup`, peer `go` flag, `WD_PEERS` |
| `android/.../SearchWindowPolicy.kt` (new) | window / retry rules (pure) |
| `android/.../NearbyBackgroundPolicy.kt` | `createFriendGroup` allowed with the app closed |
| `lib/.../nearby_friend_link.dart` (new) | name / password + who-opens / join / close rules (pure, tested) |
| `lib/.../sealing_peer_transport.dart` | keeps the link keys per friend (blocked left out) for the backup |
| `lib/app/app_dependencies.dart` | wires link keys + "message waiting" (outbox) into the backup |
| `lib/.../wifi_direct_fallback_service.dart` | backup flow (B-2…B-11), Dart timer asks native before searching (A-7) |
| `lib/.../nearby_group_planner.dart` | new cadence numbers (A-4) |
| `lib/.../wifi_direct_service.dart`, `connectivity_repository.dart`, `domain/nearby_group_control.dart` | 3 new method wrappers |
| `pubspec.yaml` + build stamp | 3.0.35+106; the version tests that check it (`nearby_190_test`, `bundle173_test`, …) are updated |

**Not touched:** the router (LAN) path, calls audio, messages / outbox logic, the server, UI screens.

---

## 6. Tests

**Unit (Kotlin / Dart, in the build):**
- names / passwords: the same on both sides, different per friend, valid for Android (`validNetworkName`, `validPassphrase`), 3 keys;
- who opens (smaller id; bigger after 30 s with something waiting; both open → bigger leaves);
- the window blocks restarts; a tap may restart once; offset 0–3 s; new cadence numbers; battery rules unchanged;
- skip reasons (on router, in group, battery, no key, Android < 10);
- the old tests for the 177 / 184 / 189 / 190 rules still pass.

**Phone tests (only these prove it):**

| # | Test | Pass |
|---|---|---|
| T1 | Router on: message, call, file | same as today |
| T2 | Router off, both apps open, send a message | arrives ≤ 30 s |
| T3 | Router off, call | rings ≤ 30 s, voice OK for 2 min |
| T4 | Router off, the ZTE app closed (service on), send from the Realme | arrives ≤ 2 min |
| T5 | The same as T4 but the other way round | arrives ≤ 2 min |
| T6 | Router off → on during a call | call not cut, later router-first |
| T7 | Both send at the same moment | one group, both arrive |
| T8 | Battery ≤ 10%, app closed | no search (log `WD_FRIEND_SKIP why=battery`) |
| T9 | Router off for 30 min, nothing sent | group closes after 3 min idle and opens again when you send |
| T10 | Logs after T2–T4 | `WD_SEARCH`, `WD_SIGN` / `tag found`, `WD_FRIEND_*` lines show each step |

---

## 7. Risks (honest)

1. **The sign may still not come** after Part A on these two phones. That is why Part B exists: it needs no sign.
2. **App closed on the receiving phone:** it only sees the friend group while its own peer search runs
   (every 60 s with something waiting, 3 min otherwise). So T4/T5 target 2 min, maybe up to 3–4 min.
3. A nearby TV/printer that hosts Wi-Fi Direct can be tried once by mistake (25 s, then skipped 5/30 min).
4. A Wi-Fi Direct group uses more battery than idle. That is why there is the 3 min idle close and the battery rules.
5. Only a compile check is possible here. **No success claim until T1–T10 pass on your phones.**

---

## 8. Decisions (your answers, 3 Nov)

- **Q1 = a.** The smaller device id opens the friend group and the other phone joins. The bigger id opens itself only if it has a message or call waiting and has seen no group for 30 s.
- **Q2 = a.** Without the router, friends stay connected even when nothing is being sent, so their status shows Nearby and calls go through at once. The battery rules (A6) and the 3 min idle close for groups with no member still apply.
- **Q3 = a.** The existing "Allow location all the time" card on the Keep-running screen is reused as it is. (I checked the code: there is no separate Nearby check list, so the card stays only there. Adding it anywhere else would be new UI and need a mock first.) Nothing is switched on without you. **Update while building:** the card is not needed for 200 any more (no Wi-Fi list reading; see §3). Nothing changed on that screen.
- **Q4 = b.** 200 = the backup for **2 friends**. A bigger version for more friends will be planned later as its own bundle (TODO_201, see §9).

## 9. Later (not in 200): TODO_201 multi-friend backup

- One phone links 3+ friends without signs: the host opens one group and its friends join with their own pair names. This needs a new "group host for many friends" rule.
- Phones that are friends of different people (A–B, B–C) link through B (mesh hop).
- It will be planned after the T1–T10 results of 200, so it builds on what works on your phones.
