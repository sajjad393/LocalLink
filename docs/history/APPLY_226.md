# APPLY 226 - Bluetooth LE finds friends, Wi-Fi still carries everything (app 3.0.66+137, app only)

**Order:** push **224 first** (`locallink_app_224_2026-11-08.zip`), then **225** (`locallink_app_225_2026-11-08.zip`), then this 226 zip.
**No backend, no database.** Kotlin: yes (2 new files). **New permissions:** Bluetooth scan + advertise (Android 12+). There is no Bluetooth connect permission.

## PowerShell

```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_app_226_2026-11-09.zip" -DestinationPath .
flutter pub get
flutter test -j 1
git add -A
git add -f APPLY_226.md TODO_226.md
git commit -m "v3 3.0.66+137 bundle 226: Bluetooth LE finds friends (tiny advert with a wants flag, join the friend group by name at once, search together), Allow and Bluetooth off cards in Add Contact Nearby"
git push
```

Build and install the APK as usual (the Kotlin part needs a full build, not a hot reload).

## What changes for the user
- **Add Contact -> Nearby**, under the "Nearby" title. There is at most one card at a time, and the Wi-Fi "Allow nearby" card wins:
  - Android 12+, Bluetooth not allowed: **"Faster connect with Bluetooth" / "Find friends in seconds." [Allow] x**.
    - Android 13+ with "Nearby devices" already allowed: no pop-up, the card just goes away.
    - Android 12: one pop-up.
  - Bluetooth off: **"Bluetooth is off" / "Turn it on for faster connect" [Turn on] x**. Turn on opens the Bluetooth settings; the app never turns Bluetooth on itself.
  - x hides that card for 7 days. Neither card ever asks by itself.
- **Nothing else on the screen changes.** Chats, files and calls still go over Wi-Fi (router / Wi-Fi Direct / mesh). Bluetooth only says "I'm here / I want you".
- **Expected:** a friend coming back in range links in ~5-15 s with the screen on (225: 15-35 s). With the screen off it is ~10-30 s; strict phones like ZTE may pause scans.
- Bluetooth off or not allowed, or Android 9 -> works exactly like 225.

## How it works (short)
- Each phone sends a tiny Bluetooth advert (10 bytes, ~1 per second). It holds its short id (the same 8-hex id the Wi-Fi Direct tag shows today) and the short id of the friend it wants (call first). Flags: host, member, searching now, on router, call, pair.
  - **No name, no password, no account data.**
- **Ali hears Sara (a friend) asking for him and hosting their pair group** -> Ali joins it **by name at once**, with no Wi-Fi Direct search (`WD_FRIEND_JOIN reason=ble_wants_me`).
- **Sara wants Ali but is not hosting yet** -> the smaller id opens the pair group at once (`ble_open`). The other phone waits for the pair flag, then joins.
- **Both host** -> the bigger id leaves and joins (`ble_both_host`).
- **A LinkUp phone is "searching now"** -> this phone searches at once too (max once per 60 s), so both search at the same moment. This helps strangers and new groups.
- **Never:**
  - during a live call (the Bluetooth scan stops too, to protect the voice);
  - when both phones are on the same router;
  - leaving a group that has other people;
  - touching another app's group;
  - with Nearby off;
  - with battery <= 10% and the app closed.
- **Android 10-11:** with the app closed, Bluetooth scans need location "Allow all the time" (already asked since 177).

## Log tags (226)
- `BLE_STATE state=on|off|no_permission|unsupported|scan_only`
- `BLE_SCAN start mode=low_power|balanced|low_latency` / `BLE_SCAN stop why=call|idle`
- `BLE_ADV start mode=...`
- `BLE_SEEN id=<8 hex> wants_me=y host=y pair=y call=y searching=n rssi=-60` (one per phone per minute)
- `NEARBY BLE wants=...`, `NEARBY BLE search_echo id=...`
- `WD_FRIEND_JOIN ... reason=ble_wants_me`, `BLE_JOIN friend=... after_ms=...`
- `BLE_THROTTLED`, `BLE_REST`, `BLE_PERM asked|granted|denied`

## Files
- `android/app/src/main/AndroidManifest.xml`: +4 Bluetooth permissions, plus bluetooth_le marked not required.
- NEW `android/.../NearbyBle.kt` (engine), NEW `android/.../NearbyBlePolicy.kt` (pure rules)
- `NearbyRadio.kt` (start/stop, 2 methods, call pause), `NearbyBackgroundPolicy.kt` (2 methods allowed in background), `MainActivity.kt` (Allow + settings, through PermissionQueue)
- NEW `lib/features/connectivity/data/services/nearby_ble.dart`
- `wifi_direct_fallback_service.dart`, `nearby_friend_link.dart`, `wifi_direct_service.dart`, `connectivity_repository.dart`
- `lib/features/directory/presentation/nearby_people_section.dart` (2 cards)
- `app_dependencies.dart`, `app_build.dart`, `pubspec.yaml` (3.0.66+137)
- NEW tests:
  - Kotlin: `BlePacket226Test`, `BleRate226Test`, `BleMode226Test`
  - Dart: `test/friend_ble_226_test.dart` (planner rows + service + advert), `test/ble_cards_226_test.dart`
- Old tests changed (expectation only):
  - `test/bundle210f_screen_test.dart:45`: permission count 21 -> **25** (+4 Bluetooth lines).
  - Version pins in `test/bundle223_logs_test.dart` and `test/nearby_190_test.dart`.
  - Nothing else.
- Not touched (the TODO listed them but they did not need a change): `LocalLinkTransportService.kt`, `nearby_group_control.dart`.

## Phone tests (226) - Extended RAM OFF; test order: router -> Wi-Fi Direct -> mesh
1. **Allow card:** Add Contact -> Nearby shows the card. Tap Allow:
   - Android 13+: no pop-up, the card goes away.
   - Logs: `BLE_PERM asked`, `BLE_PERM granted`, `BLE_STATE state=on`.
2. **Bluetooth off:** the "Bluetooth is off" card appears. Turn on opens Bluetooth settings. Turn Bluetooth on, come back -> the card is gone.
3. **Router:** no change (~3 s).
4. **Wi-Fi Direct comeback, screen on:** phones apart, call Ali ("Waiting for Ali to connect..."), bring Ali's phone back with its screen on. Note the seconds until "Ringing..." (aim <= 15 s). Logs: `BLE_SEEN`, `WD_FRIEND_JOIN reason=ble_wants_me` or `ble_open`, `BLE_JOIN`.
5. **Same with Ali's screen off and app closed.** Test on C71, Note 60x and ZTE.
6. **Live call 5 min** with Bluetooth on: no stutter compared with 225. Logs: `BLE_SCAN stop why=call` and a start again after the call.
7. **Bluetooth off on one phone:** everything works as in 225.
8. **Mesh A<->B<->C:** unchanged (A calls C through B -> "Calling...").
9. **Day test (ZTE):** LinkUp battery use before vs after.

Send logs from both phones for tests 1, 4, 5 and 6.
