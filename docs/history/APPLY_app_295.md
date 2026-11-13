# APPLY app 3.0.93+164 (TODO 295: mesh call truth + ghost ring + quick re-host + faster recovery check + profile loading)

Zip: `locallink_app_295_2026-11-14.zip`, on top of GitHub `b5744ef` (3.0.92+163).
No backend change.

## What changes
- A (ghost ring): while your friend's phone rings, your phone repeats the call every 5 s. If those
  repeats stop for 12 s (your cancel could not reach them), their phone stops ringing and shows
  "Missed call". Calls from an older LinkUp, or calls the server knows, ring 30 s as before.
- G1 (the answer is the proof): you call over a stored mesh way and get no answer in 6 s:
  - that way is dropped and the neighbours are asked again; for 15 s the same next phone is not
    believed for this friend (its own table is old too). A direct link is never dropped.
  - the friend goes grey at once on the map card and in chats (no 20 s wait).
  - the call screen says "Waiting for <name> to connect…", Nearby searches, the call waits 60 s.
  - colour comes back only when something arrives from the friend's phone, or a direct link to it.
- B (honest log): `CALL_INVITE_SENT ... route=none` (no way), `route=unproven` (stored mesh way, not
  answered yet), `route=ok` (direct link).
- C (quick re-host): the phone that hosted the Nearby group and lost Wi-Fi Direct for less than
  10 s makes its group again at once (log `group resume ... rehost=1`, `reason=rehost_p2p`).
  Was: idle -> 20 s search -> create (29 s on the ZTE).
- D: recovery password check about 3x faster (same maths, old passwords keep working).
- E: 10 px gap between the password box and "Show my code".
- F: profile screen shows the saved profile at once; only with nothing saved yet it shimmers
  (no "LinkUp user"); no display name -> username without @, grey @username line stays.

## Files
Dart: `call_session_manager.dart`, `presence_hub.dart`, `app_dependencies.dart`,
`wifi_direct_transport_service.dart`, `wifi_direct_fallback_service.dart`,
`host_rehost_295.dart` (new), `password_kdf.dart`, `recovery_code_286.dart`, `account_bloc.dart`,
`profile_screen.dart`, `profile_shimmer_295.dart` (new), version files.
Kotlin: `LocalLinkTransportService.kt`, `mesh/MeshUnproven295.kt` (new), `MainActivity.kt`,
`BackgroundChannels.kt` (method `dropUnprovenRoute`).
Tests: new `test/call_295_test.dart` (19), `test/rehost_295_test.dart` (8),
`test/profile_295_test.dart` (6), `test/password_kdf_295_test.dart`, Kotlin `Unproven295Test` (4).

## Tests (here)
- `flutter analyze`: 0 errors; no new warnings in changed files.
- Full Flutter suite: 298 files, 10 chunks, 2896 tests, all passed. One chunk first failed in
  `seal_relay_156_test` (old random flake: the sealed text can contain "hi"); it passes alone and on
  the re-run of the whole chunk.
- Kotlin: compile clean; all JVM unit tests 477/477 OK.
- Old tests changed: version lines in `bundle223_logs_test` / `nearby_190_test` only. Nothing removed.
- NOT checked here: real phones, radios, calls. Release APK: CI builds it.

## Phone check
1. Install 3.0.93 on all phones.
2. 3 phones A - B - C (C reached only through B). A calls C, then turn off B's Wi-Fi:
   A shows C grey within ~6-8 s, screen "Waiting for C to connect…". B back -> C in colour only
   after C is heard; the call rings if within 60 s.
3. Ghost ring: A calls C, C rings, turn off B's Wi-Fi, cancel on A -> C stops ringing ~12 s later
   with "Missed call".
4. ZTE as host: when `WD_P2P state=on` follows a short off, `group create` within ~3 s.
5. Recovery: password check faster, button not touching the box. Profile: no "LinkUp user" flash.
