# TODO 225 + 226 — Calls and links come back fast when a friend returns

Status: **PLAN ONLY. Freeze is ON. No code until you say "go ahead 225" (and later, separately, "go ahead 226").**
Base: app 224 (`b3246a7`, 3.0.64+135, waiting for your push). Backend: no change in either bundle.

| Bundle | What | Version | Native (Kotlin) | New permission | Risk |
|---|---|---|---|---|---|
| **225** | Wi-Fi only: "a call wakes Nearby" | 3.0.65+136 | no | no | low |
| **226** | Bluetooth LE finds friends, Wi-Fi still carries everything | 3.0.66+137 | yes | yes (Bluetooth, Android 12+) | medium |

226 is built only after 225 is pushed and tested on phones.

---

## 0. Your decisions (2026-11-08)

- [x] Split: **225 = Wi-Fi fix, 226 = Bluetooth**, both written here, built one at a time.
- [x] Bluetooth permission: **a card in Add Contact (the Nearby part; there is no separate Nearby screen any more) with an "Allow" button.** Never a surprise pop-up.
- [x] Bluetooth OFF: **a small hint "Turn on Bluetooth for faster connect" + a button that opens Bluetooth settings.** The app never turns Bluetooth on by itself.
- [x] Calling a friend who is away: **keep trying 60 s, showing "Waiting for <name> to connect…"**.
- [x] Standing rules: the app must stay stable; no new issues; the freeze stays on; only the files listed here; old tests unchanged (if one must change, only setup or an expectation is added, and I tell you).

## 1. The problem (what the logs and the code show)

Example: you call Ali. Ali is away. Ali walks back after 10 s.

| Step | Now (224) |
|---|---|
| Call starts | The call checks every 5 s "is there a link?". It **does not start a search**. |
| Search | Runs on its own timer: app open 30 s; app closed + something waiting 60 s; app closed idle 3 min. |
| Ali's phone | On Wi-Fi Direct a phone is only seen **while it searches itself**. Ali's phone doesn't know you call; it searches only on its own timer. |
| Friend group | The pair's own group (bundle 200) opens only if the smaller id sees a phone, or the bigger id after 50 s. A ringing call counts as "busy", so "both host → the bigger moves" is blocked. |
| Give up | The call fails at **45 s** ("Couldn't reach them"); the invite leaves the queue at 60 s. |

Result: Ali is linked at ~50–60 s, the call already gave up.

Checked and **already fine (no change)**: when a link appears, the native send queue sends the waiting invite at once (it doesn't wait for the 5 s check).

---

# PART 1 — Bundle 225: "a call wakes Nearby" (Wi-Fi only)

Goal: when you call a friend who is away, both phones get linked as soon as possible, without new permissions, without touching the native code, and without changing anything for calls that already have a link.

Only applies when **all** of these are true (an "away call"):
- outgoing call, state `connecting`, the far phone has not answered "ringing" yet (`signalingConnected == false`);
- the route check says **no link** to that friend;
- no voice is playing (no live call on this phone).

Everything stops when the call rings / connects / ends / is cancelled, or after 60 s.

### P1. The call tells Nearby who it is waiting for
- [x] `CallSessionManager.startCall`: after the session is made and the first route check says no link, call a new hook `nearbyCallWait?.call(peerId, until: now + 60 s)`.
- [x] On ring / connect / end / cancel / fail: `nearbyCallWait?.call(null)` (clears).
- [x] Wire the hook in `app_dependencies.dart` → `wifiDirectFallback.callWaiting(peerId)` (same style as the existing `isBusy` hook).
- [x] `WifiDirectFallbackService.callWaiting(String? peerId)`: stores `_callTarget` + `_callUntil`, calls the existing `requestRoute(peerId)` (marks the friend "wanted" in the published tag), sets `_searchSoon = true` (the search starts on the next 5 s tick, not at the next slot).
- [x] The target clears by itself at `_callUntil` (safety if the call side misses the clear).
- [x] Logs: `CALL_NEARBY_WAIT start friend=<8 hex>` and `CALL_NEARBY_WAIT end why=rang|connected|ended|timeout after_s=N`.

### P2. Search almost all the time for ≤ 60 s
- [x] `_groupTick`: `urgent` also true while `_callTarget != null` → the existing urgent cadence (25 s; one search window is 20 s) = nearly continuous searching.
- [x] Only for an away call (no voice yet), so the "voice breaks while searching" risk (bundle 184) does not apply. The native `CallNearbyPause` still blocks searching once voice starts — no change there.
- [x] Battery: the caller's app is open (calling), so the low-battery stop rules don't apply; the 60 s limit caps it.

### P3. Open / join the friend group at once for the call target
In `nearby_friend_link.dart` (`planFriendLink`) add one input: `callTargetId` (friend device id or null). For that friend only, when this phone has **no group** (`role == none`):
- [x] a. Remembered address of the friend is hosting now → join (existing `known_host`, unchanged).
- [x] b. **New** `call_join`: a host phone without a LinkUp tag is seen → try it with the pair password, in **any id order** (today only the bigger id may). A wrong guess fails in ≤25 s and is skipped 5 min (existing skip rules).
- [x] c. **New** `call_open`: otherwise open the pair's friend group **at once**: no "phone seen" gate, no 20 s sign wait, no 50 s bigger-id wait, no open rest.
- [x] While hosting the friend group for the call target: never `idle` close until the call ends (+30 s), then the normal 3 min rule.
- [x] Phone is a **member** of another group, or **host with people in it** → keep that group (others use it; mesh may still carry the call). Only the urgent search (P2) runs. Log `WD_FRIEND plan=none reason=call_keeps_group`.
- [x] `FriendLinkFriend.pending` = true only for the call target (today a call marks **all** friends pending).
- [x] Logs: `WD_FRIEND_OPEN reason=call_open`, `WD_FRIEND_JOIN reason=call_join`.

What Ali's phone does (no change needed there, already in 200/201/205):
- It lost you lately → it searches every 30 s for 5 min (60 s until 30 min), on the same :00/:30 slots as yours.
- Its search sees your friend group (a hosting phone is visible to any phone that searches) → bigger id joins (`friend_group_seen`) / remembered address joins (`known_host`) / smaller id opens its own → both host → the bigger one moves (P4 makes that work during the call).
- Joined → the waiting invite goes out at once → Ali's phone rings.

### P4. A ringing "away call" is not "busy"
Today `isBusy = calls.session?.isFinished == false || voiceRelay.active`, so any call (even one that never reached the other phone) blocks group moves.
- [x] `isBusy` = voice relay active, **or** a call that is past the away stage: incoming (ringing or answered), outgoing with `signalingConnected == true`, `connected`, `reconnecting`, or `answeredAt != null`.
- [x] So only "outgoing, connecting, not reached yet" is not busy → `both_host` (bigger leaves and joins) and `call_join` may run.
- [x] The tag flag `call=1` (tells nearby phones "a call goes on here, don't move my group") uses the same new rule.
- [x] An incoming ringing call **stays busy** (moving groups while it rings could lose the answer).

### P5. The call screen: wait 60 s with a clear text
- [x] `CallSessionManager`: new `ValueListenable<bool> nearbyWait` (true while the away call waits; no change to the `CallSession` model or the database).
- [x] Connect watchdog: **45 s → 60 s only for an away call**. Calls that had a link at the start keep 45 s.
- [x] `call_screen.dart`, outgoing + connecting + `nearbyWait`: status text **"Waiting for <name> to connect…"** (name cut with "…" if long). Otherwise "Calling…" exactly as today.
- [x] The text never says "nearby": Ali may come back over Wi-Fi Direct, the router OR the mesh (through other phones). A mesh route counts as a link (`LocalRouteKind.mesh`, up to 8 hops), so a friend reachable on mesh never sees this text; the call goes over the mesh at once as today. If a mesh route appears while waiting, the text goes back to "Calling…" and P1–P3 stop (no group change).
- [x] Only the status string changes: same `CallHeader` status line (17 sp, w500, `CallPalette.textSecondary` grey), same avatar, name, "LinkUp voice call" label and action pill (mic / speaker / red end). No box, no new colour.
- [x] As soon as a link appears the text goes back to "Calling…", then "Ringing…".
- [x] After 60 s: the same "Couldn't reach them — try again" as today (same reason `unreachable`, so call history and the server don't change).
- [x] Invite queue lifetime stays 60 s; the 5 s resend stays (each resend has its own 60 s).

Mock: `mock_225_call.png` (NOW vs 225).

### P6. Tests (225)
New Dart test files only; old tests unchanged.
- [x] `test/call_wait_225_test.dart`: hook called on an away call, cleared on ring / connect / end / cancel; not called when a route exists; watchdog 60 s away vs 45 s normal (fake clock / injectable durations, no `fake_async`); `nearbyWait` true / false.
- [x] `test/friend_call_225_test.dart` (`planFriendLink`): `call_open` at once with no phone seen; `call_join` for any id order; member / linked host keeps its group; no idle close while calling; pending only for the target; the old rules unchanged when `callTargetId == null`.
- [x] `test/busy_split_225_test.dart`: the busy table for every call state (outgoing not reached = not busy; incoming ringing = busy; …).
- [x] `test/wd_call_cadence_225_test.dart`: urgent while `_callTarget`; `_searchSoon` set; the target clears at `_callUntil`.
- [x] `test/call_screen_225_test.dart`: the waiting text, the long name cut, back to "Calling…".
- [x] Full suite + `flutter analyze` on the touched files.

### P7. Files (225)
- `lib/features/calls/data/services/call_session_manager.dart`
- `lib/features/calls/presentation/screens/call_screen.dart`
- `lib/features/connectivity/data/services/wifi_direct_fallback_service.dart`
- `lib/features/connectivity/data/services/nearby_friend_link.dart`
- `lib/app/app_dependencies.dart`
- `lib/core/app_build.dart`, `pubspec.yaml` (3.0.65+136)
- 5 new tests above + `APPLY_225.md`, `TODO_225.md`
- Expected: 2 old tests that pin the version (`bundle223_logs_test`, `nearby_190_test`) get only the new version number (as in 224).

### P8. Expected result (225), honest
| Case | Now | After 225 |
|---|---|---|
| Same router / hotspot / mesh | ~3 s | ~3 s (no change) |
| Wi-Fi Direct, you separated < 5 min ago | 50–60 s, call often fails at 45 s | **~15–35 s, call rings** |
| Wi-Fi Direct, separated long ago, Ali's app closed | 1–3 min | still slow (Ali's phone searches every 60 s–3 min) → **Part 2 fixes this** |

### P9. Risks (225) and how they are limited
- More searching on the caller only, ≤ 60 s, only with no voice. → no call stutter, small battery.
- The caller's own friend group: opened only when the phone has no group; never closes a group with people. → no one else drops.
- A wrong `call_join` guess costs ≤ 25 s and is skipped 5 min (existing).
- An incoming ringing call stays "busy". → the answer is not lost.
- No native, no permission, no database, no server change.

### P10. Phone tests (225) — order: router → Wi-Fi Direct → mesh
1. **Router:** both on the same Wi-Fi, call → rings in ~3 s exactly as before; the text stays "Calling…".
2. **Wi-Fi Direct, come back:** Wi-Fi Direct linked, walk Ali away until "not nearby" (or turn his Wi-Fi off 1 min), call him → "Waiting for Ali to connect…"; bring him back (Wi-Fi on) within 20 s → rings before 60 s. Note the seconds.
3. **Never comes back:** call, keep Ali away → after 60 s "Couldn't reach them — try again"; no ghost ring later on Ali's phone.
4. **Mesh:** A ↔ B ↔ C linked, A calls C (C not in direct range) → normal "Calling…" → "Ringing…" over the mesh, no waiting text. Then C away, A calls → "Waiting for C to connect…"; C comes back next to B → rings over the mesh.
5. **In a group with others:** 3 phones linked, call a 4th phone that is away → the group is not broken; others still chat.
6. **Incoming while searching:** Ali calls you while your phone is waiting for someone else → normal incoming call.
7. Logs to send: `CALL_NEARBY_WAIT`, `WD_FRIEND_OPEN reason=call_open`, `WD_FRIEND_JOIN reason=call_join`.

---

### As built (225, 3.0.65+136) — small differences from the plan
- The wait lives in a new small file `call_nearby_wait.dart` (`CallNearbyWait`, a ChangeNotifier) instead of a `ValueListenable` inside `CallSessionManager`. Same idea: no change to `CallSession` or the database.
- The 5 planned test areas are in 2 files: `test/call_nearby_wait_225_test.dart` (away rule incl. mesh, busy table, end reasons, text + long name, manager start/stop, watchdog 45 s + 15 s) and `test/friend_call_225_test.dart` (planner `call_open` / `call_join` / `known_host` / `call_host_waits` / `call_keeps_group`, service urgent target, timeout, pending only target).
- Version file is `lib/core/config/app_build.dart`.
- No "+30 s" idle grace after the call: when the call rings the friend is in the group (members > 0), so idle close can't hit it.
- The tag flag `call=1` already uses the same busy rule (no extra code).

# PART 2 — Bundle 226: Bluetooth LE finds friends (Wi-Fi still carries everything)

Why Bluetooth: on Wi-Fi Direct both phones must search at the same moment, and searching all the time breaks groups and calls and drains the battery. Bluetooth LE can **listen all the time** at a very low battery cost without touching Wi-Fi. Bluetooth only says "I'm here / I want you"; chats, files and calls still go over Wi-Fi.

Applies to **Android 10+ only** (a silent friend-group join needs Android 10). Android 9 phones keep 225 behaviour.

### B1. Manifest and permissions
- [ ] `BLUETOOTH_SCAN` with `usesPermissionFlags="neverForLocation"` (Android 12+).
- [ ] `BLUETOOTH_ADVERTISE` (Android 12+).
- [ ] `BLUETOOTH` + `BLUETOOTH_ADMIN` with `maxSdkVersion="30"` (Android 10–11, no pop-up; location is already allowed there for Wi-Fi Direct).
- [ ] `<uses-feature android:name="android.hardware.bluetooth_le" android:required="false"/>` (the app still installs on phones without BLE).
- [ ] **Not** `BLUETOOTH_CONNECT` (no Bluetooth pairing, no GATT connection; Bluetooth settings open without it). One less permission.
- [ ] Android 12+: the Bluetooth permissions are in the same **"Nearby devices"** group as the Wi-Fi Direct permission. On Android 13+, if "Nearby devices" is already allowed, tapping Allow grants them **with no pop-up**. Android 12 shows one pop-up.
- [ ] Every ask goes through the existing `PermissionQueue` (223), only from the Allow card tap (your decision). "Don't ask again" → the button opens the app's settings page.

### B2. The tiny Bluetooth signal (`NearbyBlePolicy.kt`, pure Kotlin, JVM tests)
Legacy advertising (works on budget phones), non-connectable, no device name, no TX power.
- Service data with LinkUp's own 128-bit id `f65feee8-2b78-4140-ad0a-4dad883a03ef` + 10 bytes:

| Byte | Content |
|---|---|
| 0 | version (4 bits = 1) + flags: host, member, searching now, on router |
| 1–4 | my short id = the same 8-hex id the Wi-Fi Direct tag already shows (`NearbyTag.wantedIdFor(idFor(deviceId))`) |
| 5–8 | wanted friend's short id (0 = nobody) |
| 9 | bit 0 = wants for a **call** (else a message); bits 1–7 = a counter (new value = state changed) |

- 2 + 16 + 10 = 28 bytes (31 with the flags field) → fits a legacy advert.
- **No name, no password, no account data.** The same short id the Wi-Fi Direct tag already shows today, so no new privacy exposure.
- A custom format (not iBeacon / Eddystone), so `neverForLocation` doesn't filter it.
- Up to 3 wanted friends rotate every 5 s (call target first, then the oldest waiting message).

### B3. Native Bluetooth engine (`NearbyBle.kt`, runs inside the existing foreground service)
- [ ] Starts with `LocalLinkTransportService` (already a `connectedDevice` foreground service, so background scanning is allowed), stops with it.
- [ ] Advertiser: `ADVERTISE_MODE_LOW_POWER` (~1/s), TX power MEDIUM. Urgent (call wants / searching now): `LOW_LATENCY` for ≤ 60 s.
- [ ] Scanner, **always with a ScanFilter** on the LinkUp service data (needed for screen-off scanning):
  - app closed: `SCAN_MODE_LOW_POWER`;
  - app open: `BALANCED`;
  - away call / pair tap: `LOW_LATENCY` for ≤ 60 s;
  - **live call: scan stops** (budget phones share one antenna for Wi-Fi and Bluetooth; protects the voice; reuses `CallNearbyPause.inCall()`).
- [ ] Android limits: ≤ 5 scan starts per 30 s per app (`NearbyBlePolicy` counts; extra starts wait, log `BLE_THROTTLED`); a scan running 30 min gets downgraded → restart every 25 min.
- [ ] Bluetooth turned on/off → adapter receiver starts/stops at once and tells Dart (`ble_state`).
- [ ] Phone can't advertise (`isMultipleAdvertisementSupported == false`) → scan only (it still hears others; others find it via Wi-Fi as today).
- [ ] Advertise/scan fails 3 times in a row → Bluetooth part rests 10 min (never loops), log `BLE_REST`.
- [ ] Events to Dart (existing native event stream): `ble_seen` {id8, wanted8, host, member, searching, onRouter, call, rssi}, max one per phone per 2 s; `ble_state` {on|off|no_permission|unsupported|scan_only}.
- [ ] Methods: `bleStatus()`, `setBleWanted(list, urgent, searching)`, `askBlePermission()`, `openBluetoothSettings()` (`Settings.ACTION_BLUETOOTH_SETTINGS`).

### B4. What a phone does when it hears another LinkUp phone (`nearby_ble.dart` planner, pure Dart, tests)
Friends are matched by short id from the existing link keys (`friendLinkKeys`). Strangers never get the friend password.

| Heard | Action |
|---|---|
| A friend who **wants me** and is **host** | **Join the friend group by name now** (no Wi-Fi Direct search; the native join already uses name + password only). `WD_FRIEND_JOIN reason=ble_wants_me` |
| A friend who wants me, not host yet | Search soon + wait ≤ 10 s for its host flag, then join |
| A friend **I want** (call or message), it doesn't host for me | Open the pair's friend group (call: at once; message: smaller id opens, as today) + advertise "wanted = friend" (call: urgent) |
| Both host the friend group | Existing rule: the bigger id leaves and joins |
| Any LinkUp phone, not linked to me, flag "searching now" | Start my Wi-Fi Direct search at once (max once per 60 s) → **both search at the same moment** (helps strangers, new groups, mesh) |
| Both on the same router | Nothing (the LAN beacon already links in ~3 s) |

Never: leave a group that has other people for a message; act during a live call; touch a foreign (non-LinkUp) group (224 D1); act at ≤ 10% battery with the app closed (existing rule).
- [ ] Each Wi-Fi Direct search window sets the "searching now" flag while it runs.
- [ ] The Wi-Fi Direct DNS-SD search stays exactly as it is (backup for strangers, Bluetooth off, old app versions).

### B5. Add Contact cards, in the Nearby part (your decisions)
Shown in Add Contact → Nearby, right under the "Nearby" title (above the "Looking for LinkUp phones…" box), built exactly like the existing `_permissionCard` in `nearby_people_section.dart`: `Card` (tertiaryContainer at 60%, radius 20) + `ListTile` (title 16 sp, subtitle 14 sp grey) + `FilledButton` on the right, plus a small × `IconButton` after the button. An 8 dp gap is added under the card (today the card touches the box). Never a pop-up by itself.
- [ ] **Allow card** (Android 12+, permission not granted): "Faster connect with Bluetooth" / "Find friends in seconds." [Allow]. The × hides it for 7 days.
- [ ] **Bluetooth off hint** (permission OK, Bluetooth off): "Bluetooth is off" / "Turn it on for faster connect" [Turn on] → opens Bluetooth settings. The × hides it for 7 days.
- [ ] No card when: Android 9, no BLE, or everything is OK.
- [ ] The existing Wi-Fi "Allow nearby" card wins if both are needed (one card at a time).

Mock: `mock_226_nearby.png` (NOW / Allow card / Bluetooth off / card above people found).

### B6. Logs (226)
`BLE_STATE state=…`, `BLE_ADV start mode=low_power|low_latency`, `BLE_SCAN start mode=…`, `BLE_SEEN friend=<8 hex> wants_me=y host=y rssi=-60` (one per phone per minute), `BLE_JOIN friend=… after_ms=…`, `BLE_THROTTLED`, `BLE_REST`, `BLE_PERM asked|granted|denied`.

### B7. Tests (226)
- [ ] Kotlin: `BlePacket226Test` (encode/decode, bad version / length ignored), `BleRate226Test` (5 starts per 30 s, 25 min restart, 3 fails → 10 min rest), `BleMode226Test` (modes per state; live call = no scan).
- [ ] Dart: `ble_plan_226_test` (every row of the B4 table + the "never" rules), `friend_ble_226_test` (join by name without an address; skip keys), `ble_cards_226_test` (which card when; × hides 7 days; the Wi-Fi card wins).
- [ ] Full suite + analyze. Compile is not proof: phone tests are the proof.

### B8. Files (226)
- `android/app/src/main/AndroidManifest.xml`
- New: `android/.../NearbyBle.kt`, `android/.../NearbyBlePolicy.kt`
- `LocalLinkTransportService.kt` (start/stop, events), `MainActivity.kt` (4 methods, PermissionQueue)
- New: `lib/features/connectivity/data/services/nearby_ble.dart`
- `wifi_direct_fallback_service.dart`, `nearby_friend_link.dart`, `nearby_group_control.dart`, `wifi_direct_service.dart`, `connectivity_repository.dart`
- `lib/features/directory/presentation/nearby_people_section.dart` (2 cards)
- `app_dependencies.dart`, `app_build.dart`, `pubspec.yaml` (3.0.66+137)
- Tests above + `APPLY_226.md`, `TODO_226.md` (copy of this Part 2)

### B9. Expected result (226)
| Case | After 225 | After 226 |
|---|---|---|
| Friend comes back, screen on | 15–35 s | **~5–15 s** |
| Friend comes back, Ali's app closed, screen off | 1–3 min | ~10–30 s (strict phones like ZTE may pause scans with the screen off) |
| Bluetooth off / not allowed | — | same as 225 |
| Strangers / new group | 40–60 s | faster (both search together), not instant |

### B10. Risks (226)
- Bluetooth must be on; never turned on by the app. → hint card only.
- One more permission on Android 12 (no pop-up on 13+ if Nearby devices is allowed).
- OEM screen-off scan limits (ZTE, Realme) → test with the screen off; the 225 path stays as a backup.
- Wi-Fi/Bluetooth share an antenna on budget phones → scan stops during live calls; low-power modes otherwise.
- Battery: low-power advertising (~1/s) + filtered low-power scan ≈ small; check battery stats in a day test.
- Must test on C71, Note 60x and ZTE before calling it done.

### B11. Phone tests (226)
1. Allow card appears once; Allow → no pop-up on Android 13+ (Nearby devices already allowed); card gone.
2. Bluetooth off → hint; Turn on opens Bluetooth settings; turn on → hint gone; logs `BLE_STATE state=on`.
3. **Router:** no change (~3 s).
4. **Wi-Fi Direct come back, screen on:** call Ali while away, bring him back → note the seconds (target ≤ 15 s); `BLE_SEEN` + `BLE_JOIN` in the logs.
5. Same with Ali's **screen off, app closed** (C71, Note 60x, ZTE each).
6. Live call 5 min with Bluetooth on → no stutter compared with 224; `BLE_SCAN` stopped during the call.
7. Bluetooth off on one phone → everything works as in 225.
8. Day test (ZTE): battery use of LinkUp before vs after.

---

## Not in this TODO (still open in `PENDING.md`)
C71↔Note 60x acks and Phase 8 P (waiting for the Note 60x logs); block fix; video issue; Wi-Fi call gaps; Realme mic; mesh voice; group voice; notification picture; My QR place; old offline admin row; rename password check on the UI thread.
