# TODO 260: leave a dead Wi-Fi Direct group + stop the name-card storm

Status: WRITTEN, not built (freeze on; build only when the user says "Build").
Base: app `39f16da` (3.0.76+147). If TODO 259 is built first, this goes on top of it.
Plan: ONE app zip, ONE commit, next version. No backend change.
User answers (11 Nov): write both fixes (my advice); the TECNO app was NOT force-stopped by the user.
User decisions (11 Nov, later): leave a dead group after **30 s** (not 90 s), with a call / just-joined safety; a killed phone closes its old group when LinkUp opens again (A6).

## What the user saw
At 23:10 the user (C71) left the Wi-Fi with the Wi-Fi switch still ON. Noshad (Note 60x) and Ibrahim stayed on the Wi-Fi. Both showed grey on the C71 and never came back over Wi-Fi Direct.

## What the 3 logs show (10 Nov, all on 3.0.76+147)
Files:
- `uploads/LinkUp-logs-RMX5303-2026-11-10-2316.txt` (C71)
- `uploads/LinkUp-logs-RMX3938-2026-11-10-2325.txt` (Note)
- `uploads/LinkUp-logs-TECNO-BG6-2026-11-10-2325.txt` (TECNO)

Phone ids:
- C71 = `26da19f3` (tag `6440f29b`)
- Note = `d5d181c0` (tag `114686f1`)
- TECNO = `9654237e`
- `ed16a834` is most likely the ZTE (tag `8ad26b3d`). NOT VERIFIED.

### Timeline
- 22:40–22:48: the TECNO hosts the Wi-Fi Direct group `DIRECT-LL-bMieHf` (members=3). The Note joins at 22:43 as a member.
- **22:49:01: the TECNO app is killed.** The 23:25 start logs `APP_LAST_EXIT reason=force_stop code=10 ago_s=2195`. The user didn't do it, so it was most likely the phone's cleaner (HiOS Phone Master). From 22:49 to 23:25 the TECNO log has no lines at all.
- **The group stayed on anyway.** The C71 and Note list `TECNO POP 8 .../go` the whole time. At 23:25 the TECNO is still `host members=2 grp=DIRECT-LL-bMieHf`.
- The Note stays a member of that dead group from 22:43 to 23:25: `group state role=member grp=DIRECT-LL-bMieHf`.
  - It publishes `tag ... m=1 key=0` (members carry no join key).
  - It hears the C71's host tag at 23:10:41 (`tag found id=6440f29b host=true`), but the rule `member_keeps_group` keeps it where it is.
  - Battery 10% -> `NEARBY_BG_BATTERY_STOP level=10` at 23:09:51.
- C71:
  - 23:10:04 the link dies; 23:10:06 `NET_CHANGE wifi_down`; 23:10:24 both grey (`why=expiry`).
  - It hosts its own empty group `DIRECT-LL-2vVeKu` (members=0) and hears only member tags (`114686f1`, `8ad26b3d`, `key=0`). It never hears the TECNO host tag, because the TECNO app is dead.
  - The friend backup step (`nearby_friend_link.dart:305`) says `plan=none reason=host_keeps_group`.
  - 23:11:50 Wi-Fi back; 23:11:54 both Nearby again over Wi-Fi.
- Result: the Note and the ZTE sit in a group that nobody runs, and the C71 sits alone in its own group. No one moves.

### Second problem in the same logs: a name-card storm
- In 1 h, C71 received `DIRECTORY_SYNC_REQUEST` 2468x, `DIRECTORY_SYNC_RESPONSE` 1475x and `DIRECTORY_PROFILE` 494x, about 45 sync requests a minute.
  - `DIR_PUBLIC_CARD saved` 1436x (to=0c9c8e v=1) + 1174x (to=586ea6 v=2).
- The Note: `DIR_PUBLIC_CARD` 2131x, `SYNC_REQUEST` 1249x.
- The TECNO: the same saves in its short runs.
- That means DB writes, radio use and battery all the time, and the useful packets queue behind the storm.

---

## A. Leave a dead group (the main fix)

### Today (code)
- `nearby_group_planner.dart` `planNearbyGroup()`, `case NearbyGroupRole.member`: a member only moves on a user's Pair tap; otherwise `none('member_keeps_group')`.
- `wifi_direct_fallback_service.dart` `_setRole()`: "our host left" (D4) only runs when the Wi-Fi Direct group itself ends (member -> none). A group that stays up while its host app is dead is never noticed.

### A1 Notice a dead group (member side)
- `wifi_direct_fallback_service.dart`: new `_groupLinkSeenAt` (ms).
  - It is set to now when this phone becomes a member, and on every tick while ANY phone has a route of kind `wifi_direct` or `local_net`.
  - Code check (11 Nov): the service already gets outside facts through callbacks set in `app_dependencies.dart` (~238–241: `hasLocalRoute`, `lanPeerIds = () => routePolicy.lanPeerIds`). Add one more of the same kind: `groupPeerIds` (phones with a `wifi_direct` / `local_net` route; from the same route policy or `PresenceHub` route reports). If it is not set (tests), treat the group as alive.
  - The host tag of my own group heard in a search also counts as "seen".
- Dead when ALL of these are true:
  - role is member;
  - no group link for **30 s** (user's choice);
  - at least 30 s since this phone joined the group (just-joined safety: links take a few seconds to come up);
  - no call going on (`_activeCallTarget == null`) and no call waiting for a friend;
  - no create/join is pending.
- New input `groupDead` (bool, default false) in `NearbyGroupInput`.
- In the member case, `if (input.groupDead) return const NearbyGroupAction.leave('group_dead');`. It goes BEFORE the `member_keeps_group` line; the pair-tap move stays first.
- After leaving, put that group name on the cooling list for **10 min** (do not join it again), unless its host tag is heard fresh (the host app came back).
- Log: `NEARBY|group dead grp=<name> no_link_s=<n> refused=<n>` once per group. `refused` = how many `transport_connect_failed ... ECONNREFUSED` to the host address (192.168.49.1) were seen in that time. It is for the log only and does not change the 30 s rule.
- Seen in the Note log: 449x `ECONNREFUSED` to `192.168.49.1:8988`, about 24 a minute, from 22:25 to 23:08. That is the TECNO app not running.
- `_setRole()`: a member -> none from `group_dead` is a leave of our own (pending kind = leave), so D4 "host left" does not start. `_searchSoon = true` (already done on -> none).

### A2 Then join the friend who wants me
- After A1 the phone has role none. Two existing rules (code check 11 Nov, `planNearbyGroup` role none) can then take it to the C71's group:
  - step 2 `wanted_by_group`: the C71's tag lists it in its wanted set (`_waitingHashes()`);
  - step 5, the Bundle 158 bridge (`_planBridge`): a phone on Wi-Fi that sees a LinkUp phone NOT on that Wi-Fi (C71 not in `lanPeers`) joins its group while staying on Wi-Fi. One bridge per group; the smallest id goes first, the others wait 30 s more.
  - So no new join rule is needed; A1 just has to free the phone.
- NOT VERIFIED: a phone on the router Wi-Fi with role none may not search often enough to hear that tag. See A3.

### A3 Search when a friend was lost lately, also on Wi-Fi
- `NearbySearchCadence.everyMs()` (`nearby_group_planner.dart` ~241): the "friend lost lately" rule needs `!onWifi`.
- Add a new argument `lostFriendOnWifi` (default false). It is true when a friend's link died in the last 30 min while this phone stays on the router Wi-Fi. Then search every 60 s for 5 min, then every 3 min until 30 min.
- Battery rules stay first (≤10% not charging = no search; under 20% = 10 min).
- The old test `bundle205_switch_test.dart:234` `every(reconnectAgo: 0, onWifi: true) == 0` stays the same, because the new argument defaults to false.
- `wifi_direct_fallback_service.dart`: pass `lostFriendOnWifi: _friendLostAt > 0 && _usableWifi`.

### A4 The empty host (C71 side)
- The C71 hosted an empty group from before. `empty_group_closed` only runs with nobody waiting (`input.waiting.isEmpty`).
- Change: an empty host that has heard, for 60 s, a member tag of another LinkUp group with a friend in it (or with a friend in its waiting list) closes its group, so it can join that group or be joined (reason `empty_host_yields`). Only when it is not busy and has no call.
- This avoids two empty hosts waiting for each other.

### A6 A killed phone closes its old group when LinkUp opens again (user's choice)
- A killed app can't run code at that moment, so it can't close its group then. The app already asks for a temporary group (`NearbyRadio.kt:582/621/659`, `enablePersistentMode(false)`), but the TECNO kept it for 36 min anyway (still `host members=2 grp=DIRECT-LL-bMieHf` at 23:25).
- Code check (11 Nov): `NearbyRadio.kt` already reads the group at start (`NEARBY_BG_STATE when=open group=y owner=y`, ~250; the TECNO logged it at 23:25:36). Bundle 224 never closes a group LinkUp didn't make (`tags?.foreign`, the `disconnect` call ~316); keep that rule.
- `NearbyRadio.kt` (the native side, the first state read in this app run): read the group info once. When this phone is the group owner of a group whose name starts with `DIRECT-LL-`, it was made before this app run, because the app hasn't made one yet. Then `removeGroup` it (the existing code at ~322/671), once.
- Then the normal planner runs as usual: the phone makes a fresh group or joins one when needed.
- Only the owner side. A phone that is a MEMBER at start keeps the group, and A1 decides within 30 s.
- Log: `NEARBY|group leftover_closed grp=<name> members=<n> last_exit=<reason>`.
- Risk: after a normal restart (update / reboot of the app), friends linked to this phone drop for a few seconds, then re-join the new group (A2). Accepted by the user.
- Kotlin test: NEW `Group260Test.kt` (the start rule: owner + `DIRECT-LL-` -> remove; member -> keep; a foreign group name -> keep). Run the Kotlin tests (`h_ktall.sh`).

### A5 TECNO killed by the phone
- `APP_LAST_EXIT reason=force_stop` (`AppHealthPolicy.kt:22`; code 10 = user / Settings / a phone tool).
- The brand guide already exists: `background_brand_guide.dart` 'transsion', and the Phone Master screens in `VendorBackgroundIntents.kt`.
- Change: at start, if the last exit was `force_stop` and the user didn't open Settings > Apps (not knowable, so: always), show the existing "Keep LinkUp running" card again, once a day at most. No setting is changed by the app (standing rule). Log `KEEP_ALIVE_HINT|why=force_stop brand=<b>`.
- Check at build whether this card already re-appears after a force stop; if it does, skip A5.

## B. Stop the name-card storm

### B1 Cause 1: every "connected" state skips the 20 s pause
- `directory_repository.dart` `_handleTransportEvent()` ~796–806: on `state` with `connected == true` (and on `connection` connected) it does `_lastSyncAt = null; sync();`.
- The native side sends a `state` event on every `configureTransport(...)` (`LocalLinkTransportService.kt:714`). The C71 log has `DIRECT_TRANSPORT_CONFIGURED` 1031x and `type=state` 1056x in 1 h.
- So every phone runs `sync()` every few seconds. Each run:
  - broadcasts its own card (`publishOwnProfile`, gossip ttl 6);
  - broadcasts a `DIRECTORY_SYNC_REQUEST` (ttl 6);
  - every phone that gets it answers with ALL its cards, in pages, and passes the request on.
- Fix:
  - Reset only on a real change: keep `_lastConnected` and reset `_lastSyncAt` only when it goes false -> true.
  - Even then, wait at least **5 s** since the last sync, and keep the normal 20 s pause for everything else.
  - A new peer (`peer_connected`) asks only that peer, not everyone: it calls `sync()` through the same pause.
- Log once a minute at most: `DIR_SYNC_SKIP|why=cooldown n=<skipped in last min>`.

### B2 Cause 2: the same card is saved again each time
- `local_store.dart` `savePublicCard233()` ~2083 compares the whole `jsonEncode(card)`.
- `DirectoryProfile.toMap()` (`directory_models.dart:87`) adds `source` and `synced_at`, and the owner sets `syncedAt: now` every time it builds its card (`_buildOwnProfile` ~734). So every copy looks new: same version, same `updated_at`, but a different `synced_at`, so it is saved again.
- Fix: if the old copy has the same `signature` (the signed part is the same), return false. Compare `signature` before the text check.
- Do NOT move `_keepPublicCard` (code check 11 Nov): it sits at the top of `_saveVerified` on purpose (Bundle 233). The public copy must be kept even when the main row keeps a friend copy with the number and returns false. The signature check alone stops the extra saves.
- Test fakes: `friend_of_friend_233_test.dart:107` has its own `savePublicCard233` (it compares the whole text), so that test is not affected.

### B3 Fewer answers to one request
- `_handleSyncRequest()` ~1088: answer at most once per 60 s per asking phone (`origin_id`), and still pass the request on.

## C. Tests
- NEW `test/bundle260_test.dart`:
  - A1: member + no group link 30 s -> `leave('group_dead')`; 29 s -> keeps; joined less than 30 s ago -> keeps; with a call -> `member_keeps_group`; host tag heard -> keeps; after leaving, the group cools for 10 min; a fresh host tag ends the cooling.
  - A2: role none + a tag that wants me -> join (the existing rule, as a regression check).
  - A3: `everyMs(lostFriendOnWifi: true)` = 60 s for 5 min, 3 min until 30 min, 0 after; battery ≤10% -> 0; the old `onWifi: true` call stays 0.
  - A4: empty host + a member tag of a friend's group for 60 s -> `leave('empty_host_yields')`; busy -> no.
  - B1: 20 `state connected` events in 10 s -> 1 sync; false -> true -> one sync (after 5 s).
  - B2: the same card with a new `synced_at` -> `savePublicCard233` false, no `DIR_PUBLIC_CARD` line; a new version -> saved.
  - B3: 3 requests from the same phone in 60 s -> 1 answer.
- OLD TESTS: no change expected. The `member_keeps_group` tests (`nearby_155`, `nearby_group_157`, `nearby_friend_link_200`, `friend_ble_226`, `friend_call_225`) keep `groupDead` false. Version lines (`bundle223_logs`, `nearby_190`) as usual. Grep `test/` for exact source strings around `_lastSyncAt = null` and `savePublicCard233` before editing.
- Full Flutter suite + `flutter analyze`. Kotlin: A6 touches `NearbyRadio.kt`, so run the full Kotlin tests too.

## D. How to check after install (all phones on the new version)
1. All phones on Wi-Fi. Force-stop the TECNO app (the group may stay up). Within about 30–60 s the Note log shows `group dead grp=DIRECT-LL-...` and `role member->none`.
1b. Open LinkUp on the TECNO again: `group leftover_closed grp=DIRECT-LL-...` in its log.
2. Then the C71 leaves the Wi-Fi with the switch ON. Within about 2 min both friends come back as Wi-Fi Direct (C71: `SWITCH ... to=wifiDirect`).
3. Storm: in 1 h of logs, `DIRECTORY_SYNC_REQUEST` should be under about 100 (now 2468), and `DIR_PUBLIC_CARD` only when a card really changes.
4. TECNO: follow the "Keep LinkUp running" card (Phone Master > App launch > LinkUp > manage manually, all ON; lock LinkUp in recent apps).

## Risks
- A1 with 30 s: a short link drop (the logs show Wi-Fi Direct <-> mesh switches of 10–20 s) could make a phone leave a group that is still alive. Safety: links (not messages) are counted, a call blocks it, and the first 30 s after a join don't count. If it happens, the phone re-joins (the cooling ends when the host tag is heard).
- A6: a normal app restart also closes the group for a few seconds (accepted).
- A4 could close a group that someone was about to join. It only runs after 60 s and never with a call.
- B1: a real new link still syncs within 5 s.

## Open questions
- Q1: answered: 30 s with a call / just-joined safety.
- A6: answered: yes, close the leftover group on start.
- Q2: show the "Keep LinkUp running" card again after the phone kills the app (A5)? (my advice: yes, at most once a day)
