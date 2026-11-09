# TODO 226 — Bluetooth LE finds friends (Wi-Fi still carries everything)

Status: **BUILT 2026-11-09** (your "Go ahead" + "Build 226 now", on top of 224 + 225, before the 225 phone tests).
Version 3.0.66+137. Base: app 225 (`7372f28`) on 224 (`b3246a7`). Backend: no change.
Push order: **224 -> 225 -> 226**.

This is Part 2 of `TODO_225.md`, copied here with the boxes ticked, plus "As built" at the end.

# PART 2 — Bundle 226: Bluetooth LE finds friends (Wi-Fi still carries everything)

Why Bluetooth: on Wi-Fi Direct both phones must search at the same moment, and searching all the time breaks groups and calls and drains the battery. Bluetooth LE can **listen all the time** at a very low battery cost without touching Wi-Fi. Bluetooth only says "I'm here / I want you"; chats, files and calls still go over Wi-Fi.

Applies to **Android 10+ only** (a silent friend-group join needs Android 10). Android 9 phones keep 225 behaviour.

### B1. Manifest and permissions
- [x] `BLUETOOTH_SCAN` with `usesPermissionFlags="neverForLocation"` (Android 12+).
- [x] `BLUETOOTH_ADVERTISE` (Android 12+).
- [x] `BLUETOOTH` + `BLUETOOTH_ADMIN` with `maxSdkVersion="30"` (Android 10–11, no pop-up; location is already allowed there for Wi-Fi Direct).
- [x] `<uses-feature android:name="android.hardware.bluetooth_le" android:required="false"/>` (the app still installs on phones without BLE).
- [x] **Not** `BLUETOOTH_CONNECT` (no Bluetooth pairing, no GATT connection; Bluetooth settings open without it). One less permission.
- [x] Android 12+: the Bluetooth permissions are in the same **"Nearby devices"** group as the Wi-Fi Direct permission. On Android 13+, if "Nearby devices" is already allowed, tapping Allow grants them **with no pop-up**. Android 12 shows one pop-up.
- [x] Every ask goes through the existing `PermissionQueue` (223), only from the Allow card tap (your decision). "Don't ask again" → the button opens the app's settings page.

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
- [x] Starts with `LocalLinkTransportService` (already a `connectedDevice` foreground service, so background scanning is allowed), stops with it.
- [x] Advertiser: `ADVERTISE_MODE_LOW_POWER` (~1/s), TX power MEDIUM. Urgent (call wants / searching now): `LOW_LATENCY` for ≤ 60 s.
- [x] Scanner, **always with a ScanFilter** on the LinkUp service data (needed for screen-off scanning):
  - app closed: `SCAN_MODE_LOW_POWER`;
  - app open: `BALANCED`;
  - away call / pair tap: `LOW_LATENCY` for ≤ 60 s;
  - **live call: scan stops** (budget phones share one antenna for Wi-Fi and Bluetooth; protects the voice; reuses `CallNearbyPause.inCall()`).
- [x] Android limits: ≤ 5 scan starts per 30 s per app (`NearbyBlePolicy` counts; extra starts wait, log `BLE_THROTTLED`); a scan running 30 min gets downgraded → restart every 25 min.
- [x] Bluetooth turned on/off → adapter receiver starts/stops at once and tells Dart (`ble_state`).
- [x] Phone can't advertise (`isMultipleAdvertisementSupported == false`) → scan only (it still hears others; others find it via Wi-Fi as today).
- [x] Advertise/scan fails 3 times in a row → Bluetooth part rests 10 min (never loops), log `BLE_REST`.
- [x] Events to Dart (existing native event stream): `ble_seen` {id8, wanted8, host, member, searching, onRouter, call, rssi}, max one per phone per 2 s; `ble_state` {on|off|no_permission|unsupported|scan_only}.
- [x] Methods: `bleStatus()`, `setBleWanted(list, urgent, searching)`, `askBlePermission()`, `openBluetoothSettings()` (`Settings.ACTION_BLUETOOTH_SETTINGS`).

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
- [x] Each Wi-Fi Direct search window sets the "searching now" flag while it runs.
- [x] The Wi-Fi Direct DNS-SD search stays exactly as it is (backup for strangers, Bluetooth off, old app versions).

### B5. Add Contact cards, in the Nearby part (your decisions)
Shown in Add Contact → Nearby, right under the "Nearby" title (above the "Looking for LinkUp phones…" box), built exactly like the existing `_permissionCard` in `nearby_people_section.dart`: `Card` (tertiaryContainer at 60%, radius 20) + `ListTile` (title 16 sp, subtitle 14 sp grey) + `FilledButton` on the right, plus a small × `IconButton` after the button. An 8 dp gap is added under the card (today the card touches the box). Never a pop-up by itself.
- [x] **Allow card** (Android 12+, permission not granted): "Faster connect with Bluetooth" / "Find friends in seconds." [Allow]. The × hides it for 7 days.
- [x] **Bluetooth off hint** (permission OK, Bluetooth off): "Bluetooth is off" / "Turn it on for faster connect" [Turn on] → opens Bluetooth settings. The × hides it for 7 days.
- [x] No card when: Android 9, no BLE, or everything is OK.
- [x] The existing Wi-Fi "Allow nearby" card wins if both are needed (one card at a time).

Mock: `mock_226_nearby.png` (NOW / Allow card / Bluetooth off / card above people found).

### B6. Logs (226)
`BLE_STATE state=…`, `BLE_ADV start mode=low_power|low_latency`, `BLE_SCAN start mode=…`, `BLE_SEEN id=<8 hex> wants_me=y host=y pair=y call=y searching=n rssi=-60` (one per phone per minute), `BLE_JOIN friend=… after_ms=…`, `BLE_THROTTLED`, `BLE_REST`, `BLE_PERM asked|granted|denied`.

### B7. Tests (226)
- [x] Kotlin: `BlePacket226Test` (encode/decode, bad version / length ignored), `BleRate226Test` (5 starts per 30 s, 25 min restart, 3 fails → 10 min rest), `BleMode226Test` (modes per state; live call = no scan).
- [x] Dart: `ble_plan_226_test` (every row of the B4 table + the "never" rules), `friend_ble_226_test` (join by name without an address; skip keys), `ble_cards_226_test` (which card when; × hides 7 days; the Wi-Fi card wins).
- [x] Full suite + analyze. Compile is not proof: phone tests are the proof.

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


## As built (226)

- **Where Bluetooth runs:** `NearbyBle` starts and stops with `NearbyRadio` (already inside the `connectedDevice` foreground service), so `LocalLinkTransportService.kt` did not need a change.
- **Idle until Dart speaks:** Bluetooth scans and advertises only after Dart sends `setBleWanted` with this phone's short id. Nearby off, or battery <= 10% with the app closed -> Dart sends an empty id -> scan + advert stop (`BLE_SCAN stop why=idle`).
- **The advert follows every 5 s tick**, also while Nearby is off. It is sent only when something changed, or once a minute.
- **What this phone asks for (max 3):** 1) the friend I am calling (call bit, urgent); 2) the friend whose pair group I host (pair bit); 3) friends with waiting messages, then the oldest waiting friend.
- **Planner reasons:** `ble_wants_me` (friend hosts our pair group for me -> join by name now), `ble_open` (friend wants me, or I have a message for it, and I am the smaller id -> open the pair group; the bigger id waits for the pair bit), `ble_both_host` (both host -> the bigger id leaves and joins).
- **Join by name:** the address is `ble`. The native join already uses name + password only (Android 10+), so no Wi-Fi Direct address is needed. `ble` is never saved as a friend address. A join that never forms -> skipped 5 min (same as other joins).
- **"Searching now" echo:** a LinkUp phone that is searching and not linked to me -> I search at once (max once per 60 s; never in a live call, both on the router, Nearby off or low battery).
- **Cards:** `NearbyBleControl` is in `nearby_ble.dart` (not `nearby_group_control.dart`, so that file is unchanged). The cards get the control from `app_dependencies.dart`. No control (tests) = no card. "Don't ask again" -> Allow opens the app's settings page. A permission answer that never comes -> 60 s timeout, then the card stays.
- **Extra fix found while testing:** without it, switching Nearby off would have left the last Bluetooth advert running. Fixed before the commit.
- **Old test changed (expectation only):** `test/bundle210f_screen_test.dart:45` uses-permission count 21 -> **25** (+4 Bluetooth lines). Version pins in `bundle223_logs_test` and `nearby_190_test`.
- **Android 10-11:** a scan with the app closed needs background location ("Allow all the time"), which LinkUp already asks for since bundle 177. Without it, Bluetooth works only with the app open.
- **Future risk (not in 226):** apps targeting Android 17 (SDK 37) will need `ACCESS_LOCAL_NETWORK`. LinkUp targets a lower SDK today.

