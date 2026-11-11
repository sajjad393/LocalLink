# TODO 261: Ibrahim's card refused + fewer sync requests + no false "group dead" + reconnect after the Wi-Fi goes off

Status: BUILT as 3.0.78+149 (11 Nov, user said "Build"). See `APPLY_app_3.0.78.md`.
Base: app `a1d5c7a` (3.0.77+148). No backend change.
Plan: ONE app zip, ONE commit, next version 3.0.78+149.
User answers (11 Nov):
- Ibrahim IS in Sajjad's People list, but his calls did not ring there.
- The server stopped at ~14:33 because the PC was closed or slept. That is not a bug and is not in this TODO.
- Write TODO 261 with my advice.
- Later the same day: "When server is off and after some time i turned off WiFi no phone auto connect until i close and open all the phone linkup app." The user picked all 3 fixes (my advice), which became section G.

Logs used (all on 3.0.77+148, 11 Nov):
- `uploads/LinkUp-logs-RMX5303-2026-11-11-1503.txt` (C71, Sajjad)
- `uploads/LinkUp-logs-RMX3938-2026-11-11-1505.txt` (Note, Noshad)
- `uploads/LinkUp-logs-TECNO-BG6-2026-11-11-1505.txt` (TECNO, Ibrahim, phone `…54237e`, user `b71c0e`, old offline id `8cd082`)
- `uploads/LinkUp-logs-Z2453-2026-11-11-1504.txt` (ZTE)

Order of importance: A (Ibrahim) > G (reconnect after Wi-Fi off) > B (sync count) > C (group dead) > D (small ZTE error, optional).

---

## Build phases (in this order; build mode runs all phases without stopping)

| Phase | Part | Files | Tests | Done when |
|---|---|---|---|---|
| 1 | A: Ibrahim's card (one own profile row, card uses the account id, no self `ID_MOVED`) | `local_store.dart`, `directory_repository.dart` | A-1 … A-7 | own row fixed + card id right, tests pass |
| 2 | G: reconnect after the Wi-Fi goes off (G1 renamed host, G2 Wi-Fi gone clears cooling, G3 empty deaf host) | `wifi_direct_fallback_service.dart`, `nearby_group_planner.dart` | G-1 … G-7 | tests pass, old planner tests unchanged |
| 3 | B: sync only on a real new link + 2 min | `directory_repository.dart` | B-1 … B-3 + the 260 test change (`<= 1` skip line) | tests pass |
| 4 | C: no false "group dead" after a freeze | `wifi_direct_fallback_service.dart` | C-1, C-2 | tests pass |
| 5 | D (optional): `connectRealtime()` with no token | `locallink_api.dart` | D-1 | test passes |
| 6 | Version 3.0.78+149 (`pubspec.yaml`, `app_build.dart`, the locked version lines in `bundle223_logs_test.dart` / `nearby_190_test.dart`), `flutter analyze`, full Flutter suite in chunks, Kotlin JVM tests | as listed | all | all green |
| 7 | One app zip, `APPLY_app_3.0.78.md`, commit message (starts with `v3`), `PENDING.md` update | docs | - | zip + APPLY ready |

- No backend change, so there is no backend zip.
- Phases 1 and 3 both touch `directory_repository.dart`, and phases 2 and 4 both touch `wifi_direct_fallback_service.dart`. Each one is done and tested before the next one starts.
- A phase that needs an answer from the user is skipped and listed in the APPLY. None is expected.

---

## A. Ibrahim's card is refused everywhere (main fix)

### What the user saw
- Ibrahim's messages and calls never reach Sajjad. TECNO rang at 14:46, 14:50 and 14:58–15:02, and none of these rang on C71.
- Ibrahim added Noshad at 14:45. On the Note, the friend link was dropped.

### What the logs show
- C71: `SEAL_OPEN_FAILED reason=not_a_contact` 87× for Ibrahim. The same happened on 10 Nov. C71 has no usable key for phone `54237e`, so it cannot open anything from him, calls included.
- C71 + Note: `KEY_CARD_IN_258 from=54237e saved=n` 6×. Every card Ibrahim sends is refused.
- C71 3× + Note 2×: `ID_MOVED_OLD_CARD_SKIP old=8cd082`. The card that arrives carries Ibrahim's OLD offline id.
- Note: `FRIEND_LINK_LOCKED_OPENED` → `CONTACT_EDGE_LOCKED_MISMATCH dropped` 8× from 14:45 to 15:01. The plain copies are parked (`CONTACT_EDGE_DEFERRED`).
- TECNO's own log shows `ID_MOVED old=8cd082 new=b71c0e` at 14:27:10, 14:30:50 and 14:31:15. Each one comes right after an app or engine start.
  - The phone moves its OWN old id again on every start, which means something writes the old id back on every start.

### Cause (confirmed in code; TECNO's database not seen)
1. `lib/core/services/local_store.dart`:
   - The `profile_cache` table has `user_id TEXT PRIMARY KEY` (line ~533).
   - `saveProfile()` (~1715) does `insert … ConflictAlgorithm.replace`. Saving the profile with a NEW user id therefore adds a SECOND row, and the old row stays.
   - `profile()` (~1839) is `query('profile_cache', limit: 1)` with no `where` and no order. It gives back the first stored row, which is normally the old one.
2. Every offline → server move saves the profile with the new id and so leaves the old row:
   - `offline_account_sync_service.dart` ~368: `seeded.copyWith(userId: realId …)`
   - `account_return_235.dart` ~184: `p.copyWith(userId: userId …)`
   - `locallink_api.dart` `getProfile()` ~698 / ~727 / ~770 / ~786: saves the server profile, a row with the server id
   - `moveUserId218` (`local_store.dart` ~1970–2030) moves contacts, blocks and cards, but never touches `profile_cache`.
   - After the move, profile edits (`account_repository.dart` ~107) read `profile()`, get the old row and save it again under the old id.
3. `directory_repository.dart` `_buildOwnProfile()` (740–791):
   - It works out `userId = store.accountId ?? local?.userId`, but only uses it for the empty check.
   - The signed card uses `userId: profile.userId`, which is the local row, so it carries `offline_…8cd082`.
4. What follows, on each phone:
   - Others: `_saveVerified()` (~1257) sees an offline id that has moved (`movedId218` → `b71c0e`). It logs `ID_MOVED_OLD_CARD_SKIP` and refuses the card.
   - The card is never saved, so `contactPublicKey` on C71 has no key for `54237e`. That gives `not_a_contact`, and messages and calls are not opened.
   - Locked friend link: `_lockedSenderMatches()` (~2440) needs the `user_id` in the embedded card to equal `fromUserId`. It is `8cd082`, not `b71c0e`, so the link is dropped.
   - TECNO itself:
     1. `publishOwnProfile()` saves its own `8cd082` card on each start.
     2. `_resolveOfflineIds218()` (~1718) finds that offline id. The guard is `oldId != store.accountId`, which passes.
     3. It calls `moveFriendId218()` and logs `ID_MOVED` again. This repeats on every start.
- The cause chain matches every log line above. The two rows in TECNO's `profile_cache` themselves are NOT VERIFIED, because we can't see its database. A1 adds a log line that proves it on the first start.

### A1 One own profile row: the one for my account (`local_store.dart`)
- `profile()`:
  - If `accountId` is set and does not start with `offline_`, read the row `where user_id = accountId` first.
  - If there is none, fall back to the old `limit 1`.
- New `repairOwnProfile261()`, run once on each start (after the database opens, before the directory starts). When `accountId` is a server id and the table has a row with another id, or more than one row:
  1. Keep the newest name, username, number, privacy and picture fields. Use the row with the highest `profileVersion`, and on a tie the newest `updatedAt`.
  2. Set `userId = accountId`.
  3. Set `profileVersion = max(all rows) + 1`, so friends take it over the old copy.
  4. Set `updatedAt = now`.
  5. Delete every other row, all in one transaction.
  6. Log `OWN_PROFILE_FIXED_261 rows=<n> old=<tail6>` once.
  - No repair is needed for an offline-only account (no server id yet), so it is left as is.
- `saveProfile(profile)`: in the same transaction, delete rows whose `user_id` is not the one being saved. This keeps one phone = one account (235), and a later move can't leave two rows again.
  - `clearProfile()` and the reset table list stay as they are.

### A2 The card always carries my account id (`directory_repository.dart` `_buildOwnProfile`)
- Use `userId` (the account id) in `DirectoryProfile(userId: …)`, not `profile.userId`.
  - Exception: when `accountId` is empty or an offline id, use the local one as today.
- This is a second guard: even if a stale row is read somewhere, the card is never signed with an old id again.

### A3 Repair TECNO after the update (no user action)
- On the first start after the update:
  1. A1 fixes the row, with a higher version.
  2. `publishOwnProfile()` sees a changed card print (`_cardPrint258`), so it sends the card to every friend directly (`_cardToFriends`), plus the normal broadcast.
  3. Others save it: the id is `b71c0e`, the signing key is the same and the version is higher.
  4. `LinkKeyRefresh257` runs, `contactPublicKey` gets the key, and messages and calls open again.
- Also stop TECNO moving its own id. In `_resolveOfflineIds218()` and `_moveOfflineIds218()`, skip rows where `device_id == store.deviceId`. Instead, drop my own old card with the existing `store.dropDirectoryProfile235(oldId)`. After the fix, the log should show `ID_MOVED` no more than once on TECNO.
- The parked friend links (`CONTACT_EDGE_DEFERRED`) are tried again when the card lands, through the existing `_flushPendingEdgesFor`. If they stay parked, Ibrahim adds Noshad again (nothing new to build).
- Risk:
  - Another phone may already hold a server copy of Ibrahim's card (unsigned) with a higher version than both of TECNO's rows. Then the fixed card could still be refused.
  - Fix: A1 uses max+1 over BOTH rows. The `b71c0e` row came from the server through `getProfile()`, so it has the server's version.
  - The test `A-5` below checks this.

### A4 Any other phone with the same problem
- Every phone that started offline and later joined the server (offline → server, 218/236) may have two rows. A1 runs on all phones, so they are all fixed by the same start-up repair. No extra code is needed.

---

## B. Directory sync requests still ~900 an hour

### What the logs show
- `DIRECT_MESSAGE_PAYLOAD_PARSED type=DIRECTORY_SYNC_REQUEST` received: C71 918, Note 887 in about 1 h. That is 15 a minute.
- `DIR_SYNC_SKIP why=cooldown` is written once a minute (39 lines on C71). So every phone hits the 20 s pause all the time, which means each phone still sends one request every 20 s (~180 an hour). The other phones also pass them on over LAN, Wi-Fi Direct and Bluetooth.
- TODO 260 B1 promised: "Only a real change (not connected → connected) skips the 20 s pause". That part works. But the line under it still asks for a sync on EVERY `state connected`.

### Cause (`directory_repository.dart` `_handleTransportEvent`, ~855–875)
```dart
if (edge) { _syncAgainSoon260(schedule: true); }
if (connected) unawaited(sync());   // <- runs ~1000 times an hour
```
This happens for both `state` and `connection` events. The native side sends `state connected=true` on every transport set-up, so `sync()` is called every second or so and actually runs as soon as each 20 s pause is over.

### B1 Fix
- `state` and `connection`: call `sync()` only on the edge (`if (edge) …`), and remove the plain `if (connected) unawaited(sync());`.
- Sync still runs:
  - on a real new link (edge, at least 5 s after the last one);
  - every 2 min (`_syncTimer`, `_periodicSyncInterval`);
  - at start;
  - on a friend search (`sync()` at ~1915);
  - from the directory screen.
- Nothing else changes: the cooldown, the B3 answer limit and the card print stay.
- Expected result: each phone sends about 30 requests an hour plus one per real new link, instead of ~180. The received count should drop by 5–6×.
- Risk: a new friend's cards could arrive up to 2 min later. A new link is an edge, so it still syncs within 5 s. Only a link that was never down waits for the 2-min cycle, and nothing new happens on such a link.

---

## C. A false "group dead" right after the app was frozen

### What the log shows
- TECNO, 15:05:21: `group dead grp=DIRECT-LL-f6V4ao no_link_s=152 in_group_s=287`.
- The TECNO app had no lines from about 15:02:49 to 15:05:21 because the phone froze it (screen off / cleaner). The 5 s group tick did not run either.
- On the first tick after waking, `now - _groupLinkSeenAt` was 152 s, but that time was spent asleep. No new route or tag could arrive while frozen, so the phone left a group that may have been fine.

### Cause (`wifi_direct_fallback_service.dart` `_groupDeadNow()`, ~1406–1448)
- `_groupLinkSeenAt` is only moved forward while the tick runs. A tick gap counts as "no link".

### C1 Fix
- New `_groupDeadCheckedAt` (ms). At the top of `_groupDeadNow(now, busy)`:
  - If `_groupDeadCheckedAt > 0` and `now - _groupDeadCheckedAt > groupDeadMs` (30 s, while the normal tick is 5 s), set `_groupLinkSeenAt = now` (the 30 s start again) and return false.
  - Build note: the gap limit is **45 s** (`groupTickGapMs261`), not 30 s. Old 260 tests step the clock 31 s at once and must keep passing, and a 45 s gap is still 9 missed ticks. The check runs at the top of `_evaluateGroup` (`_noteGroupTick261`), so a running join does not count as a gap.
  - Always set `_groupDeadCheckedAt = now`.
- Result: after a freeze, the phone first has 30 s of real running time to hear the host or a mate. Only then can "group dead" happen.
- The A6 leftover-group close at start (260) is not touched.
- The current 260 test (20 s + 11 s steps) still passes, because each step is under 30 s.
- Do not touch the `lastGroupChangeAt` lines in `NearbyRadio.kt` (`Call189Test` counts them). This fix is Dart only.

---

## D. (Optional, small) ZTE start error

- ZTE: 3× `uncaught_async_error Null check operator used on a null value` at `LocalLinkApi.wsHeaders` (`locallink_api.dart:233`). It is called from `connectRealtime()` (:1479) ← `runInitialBurst` (`reliable_messaging_service.dart:578`).
- The ZTE is phone-only and has no device token. `wsHeaders` throws before a Future exists, so the `.catchError` in `runInitialBurst` never sees it.
- Fix: make `connectRealtime()` `async` and return quietly when `store.deviceToken` or `store.deviceId` is empty. Nothing else changes, and the realtime link is not affected on phones with a token.
- Harmless today (only error lines). It is included because it is a 3-line change in a file the build already touches. Drop it if the user wants the smallest build.

## G. Phones don't reconnect after the Wi-Fi goes off, until LinkUp is reopened

### What the user saw
The server was already off. The user turned the Wi-Fi off at ~14:55:53, and no phone came back over Wi-Fi Direct until LinkUp was closed and opened on every phone (14:56:56–14:57:28).

### What the logs show (11 Nov)
- Each phone dropped the Wi-Fi: C71 14:55:53, ZTE 14:55:56, Note 14:56:08, TECNO 14:56:24 (`NET_CHANGE wifi_down`). Each phone then remade its Wi-Fi Direct group under a NEW name:
  - C71: `iqBzBe` (14:54:57) → left 14:55:20 → `f6V4ao` (14:55:51)
  - Note: `3tyQmY` (14:55:49) → left 14:56:13
- **Note:**
  - 14:55:15: hears C71's host tag (still `iqBzBe`).
  - 14:55:23 and 14:56:14: tries to join `iqBzBe`, a name C71 no longer had (the tag is 59 s old; tags are trusted for 90 s, `NearbyGroupRules.freshMs`). Both tries end with `group join timed_out` after 25 s.
  - 14:56:38: makes its own empty group `zWtbLB`.
  - 14:56:41: hears C71's NEW host tag (`f6V4ao`). By the merge rule it should move into C71 (same size, smaller id wins). Instead it logs `host_waits` until the restart.
  - Why: the 2 failed joins put C71's address into `_coolingUntil` for **10 min** (`wifi_direct_fallback_service.dart` ~1172–1175: "Two failed joins: treat that host as full"). The merge rule skips cooled hosts (`nearby_group_planner.dart` ~493 `input.cooling.contains(other.address)`).
  - 14:57:22: LinkUp is reopened. The in-memory cooling is gone, and at 14:57:52 Note logs `merge_into_bigger` → joins `f6V4ao` (Nearby again at 14:57:58).
  - **This is why reopening "fixes" it.**
- **ZTE:**
  - 14:55:58: joins `iqBzBe` (C71's old name) → timed out.
  - 14:56:26: joins `3tyQmY` (Note's old name) → timed out.
  - 14:56:52: joins `f6V4ao` (the right one), but the app was closed at 14:56:56.
  - After the reopen it runs its own empty group `MGVb7m` and never hears C71's host tag while it is a host. It does hear Note and TECNO as members (`m=true`). C71 hears the ZTE (`host=true n=0`), but C71 is the bigger group, so it waits.
  - 15:03:43: the ZTE closes its empty group (the 3-min rule `emptyHostMs`, counted again after each restart). 11 s later it hears C71 and tries to join (`wanted_by_group`). The join timed out at 15:04:22. The C71 log ends at 15:03:59, so the reason is NOT VERIFIED.
  - The ZTE system also turned its Wi-Fi Direct off twice (`WD_GROUP_LOST … why=p2p_off` 14:57:41, 14:58:07). That is the phone, not LinkUp, so it's not fixed here.
- **TECNO** came back by itself: 14:56:58 member of C71's `f6V4ao`, 34 s after its own Wi-Fi went off. So auto-connect works when no failed tries come first.

### G1 A failed try on an OLD group name doesn't mark the phone "full"
- `wifi_direct_fallback_service.dart`:
  - When a join is planned (~1883, `_pendingHost = …`), also keep the group name tried: `_pendingGroup261 = plan.host?.group`.
  - In the join-failed path (~1170–1176), store it with the failure: `_failedGroup261[host] = group`.
- New `_forgetRenamedHosts261(now)`, called at the top of each group tick next to `_coolDeadGroups`:
  - For each address in `_coolingUntil` / `_joinFailures`: if a fresh host tag from that address now shows a DIFFERENT group name than the one that failed, remove its cooling and its failure count.
  - Log once per host: `NEARBY group renamed host=<id8> cool_cleared`.
- Result: Note would have joined C71's new group about 10 s after hearing it at 14:56:41, with no restart.
- The 10-min "full" rule still works for a host that really refuses on the same group name (a full group, a wrong key).
- `_deadGroupUntil` (260 A1) is not touched.

### G2 The Wi-Fi goes off → start fresh (the same thing a reopen does)
- `_applyConnection()` (~990–997) already has the hook `if (!c.wifiNetwork && _onWifiNetwork) _searchSoon = true;` ("the router went away").
- In the same place, also clear `_joinFailures`, `_coolingUntil` and `_failedGroup261`, and log `NEARBY wifi_gone cool_cleared n=<count>`.
- `_deadGroupUntil` (dead groups, 260) and `_bridgeOffUntil` stay as they are.
- Reason: every group name changes when the Wi-Fi drops, so older failures say nothing about the new groups.

### G3 A phone alone in its own empty group closes it after 60 s when it can see another group
- `nearby_group_planner.dart`, `case NearbyGroupRole.host`, just before `return const NearbyGroupAction.none('host_waits')` (~517). Add a new rule:
  - `myMembers == 0`
  - `hostedFor >= emptyDeafHostMs` (new `NearbyGroupRules.emptyDeafHostMs = 60 * 1000`)
  - no Pair target, not busy (no call)
  - a fresh MEMBER tag (`t.member && t.group != null && t.group != input.myGroup`) is heard
  - no fresh HOST tag of that group is heard (this host can't hear the other host)
  - → `NearbyGroupAction.leave('empty_group_deaf')`.
- Unlike the 3-min rule, this one also runs when someone waits (the ZTE had `BLE wants=6440f29b`). That is the case where it matters.
- No loop:
  - After an `empty_group_deaf` leave, the service does not let this phone CREATE a group for 60 s (new planner input `noCreateUntil`). Joins are still allowed.
  - At most one such leave per 5 min.
  - Log `NEARBY group plan=leave reason=empty_group_deaf`.
- As a non-host the ZTE heard C71's host tag within 11 s (15:03:54), so it can join through the normal `wanted_by_group` / `join_nearby_group` rules.
- A member never moves (unchanged). A host with members is unchanged.
- No Kotlin change. `NearbyRadio.kt` and the `lastGroupChangeAt` count (`Call189Test`) are not touched.

### G risks
- G1/G2 clear the 10-min "full" mark more often. In the worst case, a really full host gets one extra 25 s try after it renames or after the Wi-Fi drops.
- G3 could close a group that someone was about to join. That only happens when the phone is alone for 60 s and hears another group nearby, and the 60 s no-create plus the 5-min limit stop it flapping.
- The ZTE join timeout at 15:04 (the C71 side is not in the log) and the ZTE turning Wi-Fi Direct off by itself are not fixed here. They need a new ZTE + C71 log.

---

## E. Tests (new file `test/bundle261_test.dart`; old tests unchanged)

**A (Ibrahim card):**
- A-1: `profile_cache` with two rows (`offline_x` v3, `u-real` v5), `accountId = u-real` → `profile()` gives `u-real`.
- A-2: `repairOwnProfile261()`:
  - one row is left, with `userId = u-real` and `profileVersion = 6`;
  - it keeps the newest name;
  - it logs `OWN_PROFILE_FIXED_261 rows=2` once;
  - a second run does nothing.
- A-3: `saveProfile(userId: u-real)` with an old `offline_x` row present → only `u-real` remains.
- A-4: `debugBuildOwnCard258()` with a stale local row `offline_x` and `accountId = u-real` → the card `user_id` is `u-real`.
- A-5: receiving phone:
  - It holds an unsigned server copy of `u-real` at v5.
  - It gets the fixed card (v6, same signing key) → saved, no `ID_MOVED_OLD_CARD_SKIP`.
  - A locked friend link from that phone now passes `_lockedSenderMatches`.
- A-6: `_resolveOfflineIds218()` on the phone itself, with its own old `offline_x` card on its own device id → no `ID_MOVED`, and the old card is dropped.
- A-7: offline-only account (`accountId` empty or `offline_…`) → `profile()` and the card behave as today.

**B (sync count):**
- B-1: 10× `state connected=true` with no edge, spread over 60 s (fake clock) → 0 extra `DIRECTORY_SYNC_REQUEST` after the first.
- B-2: `connected false → true` → one sync after the 5 s (as in the 260 test).
- B-3: the 2-min timer still sends one.
- The 260 test "B1 many `state connected` events -> one sync, one skip line" expects exactly 1 skip line. After the fix the extra events no longer call `sync()`, so there may be 0 skip lines.
  - That test is changed to expect `<= 1` skip line, with one sync. This is the only old-test change, and the user will be told.

**C (group dead):**
- C-1: member, no link, tick gap 150 s → no leave. Then 31 s more of ticks with no link → leave with `group dead`.
- C-2: the existing 260 "no link inside the group for 30 s" test passes as is.

**G (reconnect after Wi-Fi off):**
- G-1 (service harness): join to host A with group `g1` fails 2× → A is cooled. Then a fresh host tag from A with group `g2` → cooling cleared, the merge or join into `g2` happens, and `group renamed` is logged once.
- G-2: the same 2 failures, but A's tag still shows `g1` → A stays cooled for 10 min (old rule kept).
- G-3: cooled host + `wifiNetwork` true → false → cooling and failures empty, `wifi_gone cool_cleared` logged. `deadGroupCooling` is unchanged.
- G-4 (planner): host, 0 members, hosted 61 s, a fresh member tag of group `X`, no host tag of `X` → `leave('empty_group_deaf')`. At 59 s → `host_waits`.
- G-5 (planner): the same, but the host tag of `X` is heard → the normal merge rule (no deaf leave).
- G-6 (planner): the same with a Pair target, or busy → no deaf leave.
- G-7 (service): after a deaf leave, no `create` for 60 s, and a second deaf leave within 5 min is not done.
- The existing planner tests (`nearby_group_planner` / bundle 157–260 tests) pass unchanged.

**D (optional):**
- D-1: `connectRealtime()` with no token → completes, nothing thrown.

**Full run:** full Flutter suite in chunks, Kotlin JVM tests (no Kotlin change expected), `flutter analyze` with no new issues.

---

## F. How to check after install (all 4 phones on 3.0.78+149, server ON for the first start)
1. TECNO log: `OWN_PROFILE_FIXED_261 rows=2` once on the first start (this proves the cause), then no more `ID_MOVED old=8cd082` lines.
2. C71 + Note: `KEY_CARD_IN_258 from=54237e saved=y` (or a `DIR_PUBLIC_CARD` from b71c0e). No more `ID_MOVED_OLD_CARD_SKIP` and no `SEAL_OPEN_FAILED reason=not_a_contact` for Ibrahim.
3. Ibrahim sends Sajjad a message and calls him → it arrives and rings on C71.
4. Ibrahim adds Noshad again if Noshad doesn't see him → no `CONTACT_EDGE_LOCKED_MISMATCH`.
5. After 1 h: `DIRECTORY_SYNC_REQUEST` received per phone about 150–250 (was ~900).
6. Turn a phone's screen off for 3+ min while it is a group member, then on → no `group dead` within the first 30 s.
7. With all 4 phones linked over the Wi-Fi, turn the Wi-Fi (router) off and do NOT reopen LinkUp:
   - Within about 1–2 min they find each other over Wi-Fi Direct.
   - Logs show `wifi_gone cool_cleared`, and maybe `group renamed … cool_cleared` or `empty_group_deaf`.
   - No phone stays alone with `host_waits` for minutes.
   - If the ZTE still stays out, send the ZTE + C71 logs together.

## Risks
- A1 changes the one table every screen reads for "me". The fallback keeps today's behaviour when there is no server id, and the tests cover offline-only accounts.
- A friend whose phone stored a higher server version than TECNO knew could still refuse the card once. The max+1 over both rows should cover it (test A-5). If not, the 258 card question (`DIRECTORY_CARD_ASK_258`) asks again.
- B: new cards may come up to 2 min later on a link that never dropped (no real loss).

## Not in this TODO
- Video (stopped by the user), mesh voice (works), Realme mic.
- The server going down at 14:33 (the PC was closed).
- Wi-Fi call gaps, the ZTE day test, group voice 250/251, and the read-tick and ack items stay in `PENDING.md`.
