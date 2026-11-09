# TODO 224 - stability fixes from the 223 phone logs (Wi-Fi Direct, add contact, quiet logs)

Status: **WAITING FOR "GO AHEAD"** (freeze is on). Written 2026-11-08.
Goal (your words): **"make app stable, don't make new issue"**.
Version: **3.0.64+135**. App only. **No backend change. No phone database
change. No new screen or button** (so no mock is needed).

Sources: the 9 logs of 3.0.63+134 in `uploads/`:
- Realme C71 (RMX5303):
  - 2026-11-06: 1939, 2217, 2312
  - 2026-11-07: 0229, 0350, 0556, 1225, 2338
- Realme Note 60x (RMX3938): 2026-11-06-2353

Code read: pushed app `4f486df` (= 223 `7712558` + the TODO/APPLY files).
Findings: `PENDING.md` section C1.

---

## Stability rules for this bundle (apply to every section)

1. **Small changes only, in the exact places named below.** No refactor and no
   renamed functions. No change to message storage, the outbox table,
   encryption, calls, groups or the server.
2. **Delivery behaviour stays the same** for messages, files and calls.
   Sections F and G only change **what is written to the log**, not what
   is sent or when.
3. Every number below (10 s, 30 s, 3 times, ...) is a named constant with a
   comment, so it can be tuned later without new logic.
4. Every new rule has a **"this must still work" test** (old behaviour) next to
   the new test. Old tests stay unchanged. If one must change, only add setup
   or an expectation, and say so in `APPLY_224.md`.
5. If a fix shows another bug in the same code, it is fixed in the same section
   and written in section J ("found while fixing").
6. Full Flutter suite + Kotlin tests + analyze before the zip. Compile checks
   are never written down as "works on the phone".

## Phases (order of work; each phase is tested before the next starts)

| Phase | Section | What | Risk |
|---|---|---|---|
| 1 | H | background start: skip the server with no address | very low |
| 2 | F, G | quiet logs (waiting messages, file stall, drop reasons) | very low (log only) |
| 3 | B | LAN beacon: one bad address no longer stops the others | low |
| 4 | C | add contact: wait up to 10 s for the other phone's address | low |
| 5 | A | never use Realme / XSHARE Wi-Fi Direct groups as ours | medium (most care) |
| 6 | D | faster Wi-Fi Direct start (TXT ask again, re-check at once) | low |
| 7 | E | stop the quick reconnect loop (flap guard) | low-medium |

Phase 5 is late on purpose: the safer phases first, so a problem in A can't
hide the others.

---

## A. Realme / XSHARE Wi-Fi Direct groups are treated as LinkUp groups (Kotlin + app) - issue 1

**What the logs show**
- 2026-11-06 21:28-21:36 (C71):
  - The C71 is a member of `DIRECT-L1-XSHARE-5G-LWHD2`. At 21:31:40 **our app
    joined it**: `group join grp=DIRECT-L1-XSHARE-5G-LWHD2 mode=password`.
  - The add-contact request was sent 7 times ("tx ok") and never got an answer.
- 2026-11-07 11:59:52 (C71):
  - The group changes from ours (`DIRECT-LL-imK8Xf`, 1 member) to
    `DIRECT-44-realme C71` with **no `group create` line** from our app, so
    something outside LinkUp made it.
  - LinkUp then publishes it: `tag published host=1 ... grp=DIRECT-44-realme C71 key=1`.
  - The Note 60x joins it (members=1, then 2).
  - Later groups: `DIRECT-97-realme C71`, `DIRECT-N7-XSHARE-5G-DGJP8`.
- Delivery confirmations between the C71 and the Note 60x stop around the same
  time (C1 problem 1).

**Cause (code)**
- `NearbyGroupPolicy.validNetworkName()` accepts **any** `DIRECT-xx...`
  name. That's on purpose (bundle 157), so phones below Android 10 that
  create a group "the old way" (Android picks the name) still work.
- `NearbyTagManager` (line ~149) reads the current group from Android, keeps
  it if `validNetworkName` says yes, and **publishes its name + password** in
  the tag (`NearbyTagPolicy` line ~100: `txt["g"]`, `txt["k"]`).
- The other phone decodes it (`NearbyTagPolicy` line ~223) and the planner
  joins it.
- A phone has **one** Wi-Fi Direct group at a time. When Realme Share / XShare
  / the system takes it, LinkUp thinks it is its own group.

**Change**

A1. Kotlin `mesh/NearbyGroupPolicy.kt`: new function
`isLinkUpGroup(name: String?, legacyOwn: Boolean): Boolean`.
- `true` when the name starts with `DIRECT-LL-` and `validNetworkName` is true.
- `true` when `legacyOwn` is true (Android < 10 and this phone created
  the group itself in the last 60 s through `createGroup(ch, listener)`).
- Otherwise `false`.
- `validNetworkName` is **not changed** (it is used by join / friend group
  code that must keep working).

A2. Kotlin `NearbyRadio.kt` `createNearbyGroup()` legacy branch (SDK < 29):
remember `legacyCreatedAt = now`, and when the group is formed, remember its
name as `legacyOwnName`. Only this phone's own legacy group counts as ours.

A3. Kotlin `NearbyTagManager.kt`, where the group info is read (`requestGroupInfo`):
- If the group is **not** a LinkUp group (A1):
  - `foreign = true`.
  - `groupName = null`, `groupKey = null` → the tag publishes **no group name
    and no password**.
  - Publish `host=0 m=0` (we are not hosting a LinkUp group).
  - Log once per name change: `WD_FOREIGN_GROUP on grp=<name> role=<host|member> members=<n>`.
- When it goes away: `WD_FOREIGN_GROUP off grp=<name> after_s=<n>`.
- `emitGroup()` adds `"foreign" to foreign` in the `my_group` event.
  The `group state` log line gets ` foreign=1` at the end when true.

A4. Kotlin `mesh/NearbyTagPolicy.kt`:
- **Publish:** add the key `lg=1` only for a legacy own group (A1 second case).
- **Decode:** keep a group name from a tag only if it starts with `DIRECT-LL-`
  **or** the tag has `lg=1`. Otherwise the tag is kept (the phone is still
  seen) but **without** `group` / `key`, and it can't be joined.
  This also protects against phones still on 223 that publish a foreign group.

A5. Dart `wifi_direct_fallback_service.dart` `_applyMyGroup()`: read
`foreign` (default false). While foreign:
- The planner input says "busy with another group": `planNearbyGroup` returns
  `none('foreign_group')`. No create, no join, no leave, no merge.
- `WD_FRIEND` returns `plan=none reason=foreign_group`.
- LAN / hotspot / mesh links keep working as now (they don't need the group).
- The log line `group plan=none reason=foreign_group` is written once per spell.

A6. Dart `nearby_group_planner.dart`: add the `foreignGroup` field to
`NearbyGroupInput` (default `false`, so all old callers and tests keep their
behaviour) and the early `none('foreign_group')` return at the top of the plan.

**What we do NOT do (decision D1, my advice):** we never close or leave the
Realme / XSHARE group ourselves. It may be the user's own file share, and
closing it would be a silent change. LinkUp waits; when the system group ends,
the normal rules run again (the `group state role=none` event comes as today).

**This must still work (tests)**
- `DIRECT-LL-xxxxxx` groups: publish, decode, join, merge, friend groups as before.
- Android < 10 own legacy group: published with `lg=1`, joinable.
- The friend group (bundle 200, `DIRECT-LL-` name made from the link key): unchanged.

**New tests**
- Kotlin `Foreign224Test`:
  - `isLinkUpGroup` for `DIRECT-LL-abc123` (yes), `DIRECT-44-realme C71` (no),
    `DIRECT-N7-XSHARE-5G-DGJP8` (no), legacy own (yes).
  - Publish with a foreign group → no `g` / `k`.
  - Decode of a foreign `g` without `lg` → no group / key.
  - Decode with `lg=1` → group kept.
- Dart `foreign_group_224_test`:
  - Planner with `foreignGroup=true` + a joinable host tag → `none('foreign_group')`.
  - Same input with `false` → the old action (join).
  - `_applyMyGroup` with `foreign: true` → no create / join call on the fake radio.

---

## B. LAN beacon: one bad address stops all of them (Kotlin) - issue 3

**What the logs show**
- `LAN_BEACON paused why=no_network wait_ms=15000` comes exactly when a
  Wi-Fi Direct group comes up, then `resumed` 15-17 s later.
- Example: 11:42:45 paused, 11:42:49 group up, 11:43:01 resumed.
  Also 02:12:28 (join) paused, 02:12:45 resumed.
- During that time no phone learns our address → add-contact fails with "no LAN
  endpoint yet" and the first message waits.

**Cause (code)**
- `LocalLinkTransportService.broadcastLanBeacon()` sends to **all** broadcast
  addresses inside **one** `try`.
- When one interface is going down (the old Wi-Fi / hotspot while Wi-Fi Direct
  comes up), its send throws "Network is unreachable". The loop stops, so the
  **other addresses (also Wi-Fi Direct) get nothing**.
- The 223-K back-off then pauses the beacon for 15 s.

**Change**

B1. `broadcastLanBeacon()`: try/catch **per address**.
- Count `ok` and `unreachable`.
- If at least one address worked → `lanBackoff.onOk()` (as now on success).
- Pause (223-K) **only if every address failed** with "unreachable".
- Other errors keep the old report.

B2. A Wi-Fi Direct group change (role or name changes in `NearbyTagManager`,
or `WIFI_P2P_CONNECTION_CHANGED` with a formed group) calls
`lanBackoff.onOk()` and sends **one beacon at once**.
New log: `LAN_BEACON resumed why=wd_group`.

B3. 223-K stays for the real case (Wi-Fi off, all addresses fail): same 15 s
pause, same single log line.

**New tests**
- Kotlin `LanBeacon224Test`, a pure helper `MeshTransportPolicy.beaconOutcome(okCount, unreachableCount, otherCount)`:
  - 1 ok + 1 unreachable → not paused.
  - 0 ok + 2 unreachable → paused.
  - 0 ok + 1 other error → report, no pause.
- The 5 old `LanBeacon223Test` tests stay green.

---

## C. Add contact over Wi-Fi Direct fails: "peer is not visible yet" (Kotlin + app) - issue 2

**What the logs show**
- 2026-11-06 21:35:10-21:35:17 (C71): 5 times
  `pair-packet tx failed: no LAN endpoint for android-6a40e775a0caa5a7 yet` →
  `PAIR_SEND_THROW` + `PAIR_TAP stage=caught` (WARN).
- Every add-contact that worked came over the hotspot (10.156.91.111 / .69 / .195),
  never over Wi-Fi Direct.

**Cause (code)**
- `sendPairPayloadInternal()` needs `lanEndpoints[target]` (learned from the
  other phone's beacon). If it isn't there **at that moment**, it fails at once.
- Section B made this worse (no beacon for 15 s after the group comes up).
- Section A sent the phones into the wrong group, where the other phone
  wasn't listening.

**Change**

C1. Kotlin `sendPairPayloadInternal()`: when there is no endpoint, **don't fail
at once**.
- In the existing background `Thread`, send our beacon once at once (so the
  other phone also answers with its beacon).
- Then check `lanEndpoints[target]` every 500 ms for up to **10 s**
  (`PAIR_ENDPOINT_WAIT_MS = 10_000`).
- Found → send as today (3 datagrams, 250 ms apart).
  Log `pair-packet endpoint found after_ms=<n>`.
- Not found after 10 s → the same error as today (same message text, so the
  Dart side and old tests behave the same).
- Only one waiting send per target at a time; a second tap while waiting
  returns the same result (no double sends).

C2. Dart `nearby_people_section.dart`: `PAIR_TAP stage=caught` with
`PAIR_SEND_FAILED` "not visible" becomes **INFO** (it is a wait, not a fault).
Other errors stay WARN. The retry loop (attempt 1..4) is **unchanged**.

**New tests**
- Kotlin `Pair224Test`: pure helper `PairEndpointWait.next(elapsedMs, found)`
  → `SEND` / `WAIT` / `GIVE_UP` at 0 / 9 500 / 10 000 ms.
- Dart: the existing pair tests stay green; one new test checks that the
  "not visible" error is logged as INFO and still retried.

---

## D. Wi-Fi Direct takes ~2 minutes to connect (Kotlin + app) - issue 4

**What the logs show** (2026-11-07 02:10, C71 and friend `2f16c0cb`)

| Time | What happened |
|---|---|
| 02:10:16 | app start |
| 02:10:41 | friend seen by name tag only (`LinkUp-2f16c0cb-w`) |
| 02:11:10 | full tag arrives; the C71 makes its own group; the friend makes one too |
| 02:11:37 | `txt_ask` → **no answer**, no second ask in that window |
| 02:12:12 | full tag arrives on the next search (friend is host) |
| 02:12:26 | merge (10 s safety wait `mergeSeenMs` + wait for the next check) |
| 02:12:28 | joined in 0.3 s, link checked in 0.4 s |

The join itself is fast. Time is lost on a missed TXT answer and on waiting for
the next check.

**Change (small, no change to the search timing rules)**

D1. Kotlin `NearbyTagManager.askTxt()`: today it asks **once** per phone per
search window.
- New: ask again up to **2 more times, 4 s apart**, in the same window, if no
  TXT has arrived from that address (`TXT_ASK_MAX = 3`, `TXT_ASK_GAP_MS = 4_000`).
- Log `WD_TAG txt_ask ... try=<1..3>`.
- `WD_TAG_FAIL ... reason=2` (busy) **does not** start an extra ask.

D2. Dart `wifi_direct_fallback_service.dart`: when a host tag is first seen and
the merge rule is only waiting for `mergeSeenMs` (10 s), start **one** timer
for the moment the wait ends, which calls `_evaluateGroup()`. Cancel it on
dispose / group change. The rules in `nearby_group_planner.dart` don't change.

**Not changed on purpose (stability):**
- The search timing (`NearbySearchCadence`: 30 s with the app open, 60 s
  closed, 5 min when linked). More searches can drop the group on some phones
  (bundle 205) and cost battery.
- The rule for who creates the group.
- The 10 s merge safety wait.

**Expected:** about 40-60 s in a case like 02:10 instead of 2 min 12 s.
The first ~25 s (Realme sends no name tag at all until a search runs) can't
be fixed by the app.

**New tests**
- Kotlin `TxtAsk224Test`: pure helper `TxtAskPolicy.shouldAsk(tries, lastAskAt, now, txtSeen)`.
- Dart: a test with a fake clock — host tag at t=0 → `_evaluateGroup` runs at
  t=10 s (not at the next search end). An old planner test checks that the
  merge still waits 10 s.

---

## E. Quick reconnect loop (Kotlin) - issue 8

**What the logs show**
- 2026-11-07 04:56-05:05 (C71): the phone `...a5a7` dialled the C71 about every
  2-5 s. 153 `LINK_AUTH legacy ... side=answer` lines in 10 min (20 per minute).
- Each time: `relay link up` → `relay link down cause=eof` within 0.1 s.
- The C71 had `...a5a7` **blocked** until 05:05:24 (`CONTACT_UNBLOCK`). After the
  unblock the loop stopped.
- 2026-11-07 02:13-02:23: `WD_REDIAL why=link_died` 11 times in 10 min.

**Cause (code)**
- In `handleLanBeacon()`, a **contact** is dialled on every beacon when
  `mayDialLanContact()` says yes. That has **no cooldown** (relays have
  `RELAY_DIAL_COOLDOWN_MS`).
- The blocked side accepts only a relay link, and the dialler closes it. Then
  it dials again on the next beacon (every ~2 s), forever.

**Change**

E1. New Kotlin `mesh/MeshDialFlapGuard.kt` (pure, testable), per peer id:
- `onLinkUp(peer, now)` and `onLinkDown(peer, now)`: a link that lived
  **< 10 s** counts as a "quick drop".
- After **3 quick drops within 2 min** → hold dialling this peer for
  **30 s, then 60 s, 120 s, max 300 s** (it doubles each time).
- A link that lives **≥ 60 s**, a network change, or the user's Pair tap
  **resets** the peer.
- `mayDial(peer, now)`: true / false.

E2. `LocalLinkTransportService.handleLanBeacon()`: before `connectLanPeer(...)`
(the contact and relay branches), also check `flapGuard.mayDial(nodeId, now)`.
Log once per hold:
`LINK_FLAP hold peer=<id8> s=<n> quick_drops=<n>`; when it ends,
`LINK_FLAP free peer=<id8>`.

E3. The `WD_REDIAL why=link_died` path (line ~2083) checks the same guard for
the group owner's id. While held: `WD_REDIAL skipped why=flap s=<n>`.

E4. Answering incoming links is **not changed** (the other phone decides).
Nothing changes for links that stay up.

**New tests**
- Kotlin `Flap224Test`:
  - 2 quick drops → still dials.
  - 3 → hold 30 s, then 60, 120, 300, 300.
  - A 60 s link → reset.
  - Network change → reset.
  - A normal link with no quick drops → never held.

---

## F. Retry spam for messages to a friend who isn't nearby (app, log only) - issue 6

**What the logs show**
- Two texts to `...380d` (not nearby after 11:53) were tried again on **every**
  flush for 19 h.
- Each time: `MESSAGE_FLUSH_ITEM status=queued` + WARN `MESSAGE_ROUTE_UNAVAILABLE`
  + WARN `MESSAGE_SOCKET_SEND_SKIPPED_NOT_CONNECTED`. 1950 + 1950 WARN in one hour.
- `MESSAGE_RETRY_BACKOFF_SKIP`: 15 293 lines in the 8 logs.
- `MESSAGE_ROUTE_SELECTED_DIRECT` is WARN for a normal send (594 per hour).

**Cause (code)** — `reliable_messaging_service.dart` (`_flush` loop):
- With no direct route and no socket, the item does `continue` with no attempt
  counted, so the back-off never applies. Every flush (every ~5 s because of
  `MESSAGE_ROUTE_AVAILABLE` events) logs it again.

**Change (only the log; the send check runs every flush as today, so a friend
coming back still gets the message at once)**

F1. `MESSAGE_ROUTE_UNAVAILABLE` + `MESSAGE_SOCKET_SEND_SKIPPED_NOT_CONNECTED`:
log **once per message per waiting spell** (first time). The spell ends when
the message is sent, removed or the app restarts. Use the 223 `LogOnce` helper.

F2. A new INFO summary every **10 min** while messages wait:
`MESSAGE_WAITING n=<count> oldest_min=<n> to=<id8 list, max 5>`.

F3. `MESSAGE_RETRY_BACKOFF_SKIP`: log once per (message id, attempt number),
not every flush.

F4. `MESSAGE_ROUTE_SELECTED_DIRECT` and `MESSAGE_ROUTE_SELECTED_SERVER` → INFO
(normal events; the log header counts them as warnings today).

F5. `MESSAGE_FLUSH_ITEM` for an item that then logs F1 is written with the F1
line only (not every flush).

**New tests** (`quiet_logs_224_test`):
- 10 flushes with no route → 1 `MESSAGE_ROUTE_UNAVAILABLE` line, and the send
  check still ran 10 times (fake transport counter).
- The route comes back at flush 11 → sent at flush 11 (same as today).

---

## G. Dropped relay messages with no reason + file stall lines (app + Kotlin, log only) - issue 7

**What the logs show**
- `DIRECT_EVENT_RECEIVED type=mesh_dropped message=`: 2202 lines in one hour
  (23:38 log), no reason.
- `RELAY file stalled ... stalls=2356`: one line every ~20 s for 11 h.

**Cause (code)**
- Native already sends a `reason` with every `mesh_dropped` (`ttl_expired`,
  `loop_detected`, `relay_plain_refused`, `relay_voice_budget`, ...), but the
  Dart log line prints only `message_id` / `transport` / `cause` / `error`.
- `noteFileStall()` logs at every plain/locked switch, forever.

**Change**

G1. Dart `_handleDirectEvent`: add `mesh_dropped` to the 10 s summary
(`_hotDirectEventTypes`) with **counts per reason**:
`DIRECT_EVENTS_SUMMARY window=10s mesh_dropped=13 drop=loop_detected:10,relay_plain_refused:3`.
- The event still goes to `mesh_bloc` and the call transport as today (only the
  log changes).

G2. Kotlin `noteFileStall()`: log the first 10 switches as now, then **one line
every 10 min** per transfer: `RELAY file stalled ... stalls=<n> (every 10 min)`.

**Why this matters:** `relay_plain_refused` would explain the C71 ↔ Note 60x
problem (normal messages refused on a relay-only link). With G1 the next logs
will show it.

**New tests**
- Dart: 5 `mesh_dropped` events with 2 reasons → 1 summary line with both counts,
  and `mesh_bloc` still got 5 events.
- Kotlin: pure helper `FileStallLog.shouldLog(stalls, lastLogAt, now)`.

---

## H. Background start calls the server with no address (app) - issue 9

**What the logs show**
- About 8 s after every `BOOT_ENGINE_DART_START` (app closed, started in the
  background), you get WARN `VERSION_RULE_SERVER_FAIL FormatException: Server
  address is required` + `ADMIN_BADGE_SERVER_SYNC failed ...`.
- Example: 05:15:08 → 05:15:16, 11:43:25 → 11:43:34, 12:24:51 → 12:24:59.
- With the app open, `SERVER_CALL_SKIPPED why=no_server` works (05:26:08).

**Cause (code)**
- `ServerReach.instance.bind(...)` is called only in
  `AppDependencies.initializeCore()`.
- `background_runner.dart` starts `adminBadges.start` / the version rule without
  it, so `_address` is null and the "no server" check is skipped.

**Change**

H1. `background_runner.dart`: right after the deps are created, call the same
`ServerReach.instance.bind(address: () => store.serverAddress, socketUp: () => socket.isConnected)`.
Use a small shared helper `AppDependencies.bindServerReach()` so both places
use one line.

H2. `ServerReach.isNetworkError` / `noteFailure`: also treat
`FormatException` with "Server address is required" as `no_server`
(belt and braces). Log INFO `SERVER_CALL_SKIPPED`, not WARN.

**New tests**
- `background_runner` test with a fake store with no address → no server call,
  1 `SERVER_CALL_SKIPPED` line.
- The 223 `server_reach` tests stay green.

---

## I. Not in 224 (stay in PENDING.md)

- **C71 ↔ Note 60x delivery confirmations** (C1 problem 1): sections A, B and G
  should remove the likely causes and show the reason. A real fix waits for
  the **Note 60x logs of 2026-11-07, 11:40-12:30**.
- **223 Phase 8 "P" (link key between paired phones, `no_local_key`)**: wait
  for those logs too.
- Search timing changes and "who creates the group" rule changes (left out for
  stability, see D).
- Sending the add-contact request through the mesh / group route (C waits for
  the address instead; smaller change).
- All older open items in `PENDING.md` (block fix, video, mesh voice, etc.).

## J. Found while fixing

(empty — filled during the work)

---

## Decisions (my advice is the default; tell me if you want the other)

| # | Question | My advice | Other choice |
|---|---|---|---|
| D1 | Phone is in a Realme / XSHARE group | **Never touch it; LinkUp waits** (no silent change) | LinkUp leaves it after 3 min if it has 0 members |
| D2 | Old phones below Android 10 running 223 or older | They must update (their group name can't be trusted without `lg=1`) | Keep accepting any `DIRECT-` name from them (keeps the bug) |

---

## Files (expected; nothing else is touched without telling you)

Kotlin (`android/app/src/main/kotlin/com/sajjad/locallink/`):
- `mesh/NearbyGroupPolicy.kt` (A1)
- `NearbyRadio.kt` (A2)
- `NearbyTagManager.kt` (A3, B2, D1)
- `mesh/NearbyTagPolicy.kt` (A4)
- `LocalLinkTransportService.kt` (B1, B2, C1, E2, E3, G2)
- `mesh/MeshTransportPolicy.kt` (B1 helper, C1 constant)
- `mesh/MeshDialFlapGuard.kt` **new** (E1)

Dart (`lib/`):
- `features/connectivity/data/services/nearby_group_planner.dart` (A6)
- `features/connectivity/data/services/wifi_direct_fallback_service.dart` (A5, D2)
- `features/directory/presentation/nearby_people_section.dart` (C2)
- `features/messaging/data/services/reliable_messaging_service.dart` (F, G1)
- `app/background_runner.dart` (H1)
- `app/app_dependencies.dart` (H1 helper)
- `core/services/server_reach.dart` (H2)

Version: `pubspec.yaml` 3.0.64+135, plus the version line the old tests check.

Tests (new):
- Kotlin: `Foreign224Test`, `LanBeacon224Test`, `Pair224Test`,
  `TxtAsk224Test`, `Flap224Test`, `FileStall224Test`.
- Dart: `foreign_group_224_test`, `wd_connect_224_test`,
  `quiet_logs_224_test`, `drop_reasons_224_test`, `background_server_224_test`,
  `pair_wait_224_test`.

Docs: `TODO_224.md`, `APPLY_224.md` (with TEST_RESULTS), `PENDING.md`.

---

## Phone tests (after push; Extended RAM OFF; order: router → Wi-Fi Direct → mesh)

| # | Test | Pass when the log shows |
|---|---|---|
| 224-A1 | Open Realme Share (or receive a file with it) while LinkUp runs | `WD_FOREIGN_GROUP on grp=DIRECT-...-realme...`; **no** `tag published ... grp=DIRECT-xx-realme`; the other phone does **not** `group join` it |
| 224-A2 | Close Realme Share | `WD_FOREIGN_GROUP off`, then a normal `DIRECT-LL-` group within ~1 min |
| 224-B | Hotspot off → Wi-Fi Direct group comes up | no `LAN_BEACON paused` at the moment the group comes up (or `resumed why=wd_group` within 1 s) |
| 224-C | Add a contact with only Wi-Fi Direct (no hotspot / router) | `pair-packet endpoint found after_ms=...` and `PAIR_ACCEPT`; no `PAIR_SEND_THROW` |
| 224-D | Both phones start LinkUp together, Wi-Fi Direct only | joined in under ~60 s; `txt_ask ... try=2` if the first ask was missed |
| 224-E | Block a friend who keeps the app open nearby for 5 min | `LINK_FLAP hold` once, then at most 1 dial per hold time (not every 2 s) |
| 224-F | Send 2 texts to a phone that is off, wait 30 min | 1 `MESSAGE_ROUTE_UNAVAILABLE` per text, `MESSAGE_WAITING` every 10 min; turn the phone on → delivered within a few seconds |
| 224-G | Normal group use for 10 min | `DIRECT_EVENTS_SUMMARY ... drop=<reason>:<n>` instead of single `mesh_dropped` lines |
| 224-H | Phone-only account, app closed, reboot | after `BOOT_ENGINE_DART_START`: `SERVER_CALL_SKIPPED why=no_server`, no `Server address is required` WARN |
| 224-R | Regression: calls, file send, group chat, hotspot share, block/unblock | all as in 223 |

Please also send the **Note 60x logs (2026-11-07 11:40-12:30)** — they decide
section I.
