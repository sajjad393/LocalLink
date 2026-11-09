# APPLY 225 - a call wakes Wi-Fi Direct when the friend has no link (app 3.0.65+136, app only, Dart only)

**Order:** push **224 first** (`locallink_app_224_2026-11-08.zip`), then this 225 zip.
**No backend, no database, no Kotlin, no new permission.** Bluetooth comes in 226 (after 225 is tested).

## PowerShell

```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_app_225_2026-11-08.zip" -DestinationPath .
flutter pub get
flutter test -j 1
git add -A
git add -f APPLY_225.md TODO_225.md
git commit -m "v3 3.0.65+136 bundle 225: a call to a friend with no link wakes Wi-Fi Direct (urgent search, open/join the pair group at once), Waiting for <name> to connect, away call tries 60 s"
git push
```

## What changes for the user
- You call Ali and there is **no link at all** to Ali (no router, no Wi-Fi Direct, no mesh):
  - the call screen says **"Waiting for Ali to connect…"** (no "nearby", no Wi-Fi words);
  - your phone searches almost all the time and opens / joins your and Ali's friend group **at once**;
  - when Ali's phone joins, the text changes to **"Calling…"** and then **"Ringing…"** as today;
  - the call keeps trying **60 s** (was 45 s), then "Couldn't reach them — try again".
- A call that already has a link (router, Wi-Fi Direct **or mesh**) is unchanged: "Calling…", 45 s.
- Expected: about 15-35 s when Ali comes back in range (Ali's phone must do its own search; Bluetooth in 226 makes this faster).

## How it works (short)
- **Away call** = outgoing + still connecting + the invite has not reached Ali + no route (LAN / Wi-Fi Direct / mesh). New file `call_nearby_wait.dart` (`CallNearbyWait`).
  - Logs: `CALL_NEARBY_WAIT start friend=<8 hex> call=...` / `end why=route|rang|connected|ended after_s=`.
  - A route that comes back stops the wait at once (`why=route`).
- **P1/P2 Nearby:** `WifiDirectFallbackService.callWaiting(id)` → `requestRoute` + search on the next 5 s tick + the urgent search cadence while the call waits (max 65 s, then it clears by itself).
  - Logs: `NEARBY call_wait start friend=` / `call_wait end why=call_side|timeout|replaced`.
  - Only the call's friend is marked "pending" (before: a call marked every friend pending).
- **P3 friend group** (`planFriendLink`, phone with no group):
  - Ali's remembered address is hosting → join (`known_host`);
  - else a host phone without a LinkUp tag → try it with the pair password in **any id order** (`call_join`; a wrong guess fails in ≤25 s and is skipped 5 min);
  - else open the pair group **now** (`call_open`: no "phone seen" gate, no sign wait, no rest).
  - Hosting the pair group for the call: never idle-closed while the call waits (`call_host_waits`).
  - Member of another group / host of a normal group → keeps it (`call_keeps_group`); only the urgent search runs.
- **P4 busy:** a call that has not reached Ali yet no longer blocks group moves (so "both host → bigger id moves" works during the call). A ringing / live / incoming call still blocks them, as before.
- **P5 watchdog:** 45 s as before; a call that was away gets 15 s more once (`CALL_CONNECT_WATCHDOG_EXTEND`), then `CALL_CONNECT_WATCHDOG_TIMEOUT` → "Couldn't reach them — try again".

## Files
- NEW `lib/features/calls/data/services/call_nearby_wait.dart`
- `lib/features/calls/data/services/call_session_manager.dart`
- `lib/features/calls/presentation/screens/call_screen.dart`
- `lib/features/connectivity/data/services/wifi_direct_fallback_service.dart`
- `lib/features/connectivity/data/services/nearby_friend_link.dart`
- `lib/app/app_dependencies.dart`
- `pubspec.yaml`, `lib/core/config/app_build.dart` (3.0.65+136)
- NEW tests: `test/call_nearby_wait_225_test.dart`, `test/friend_call_225_test.dart`
- Old tests: only the version number changed in `test/bundle223_logs_test.dart` and `test/nearby_190_test.dart` (3.0.64+135 → 3.0.65+136), as in 224. Nothing else.
- Full suite here: 2302 tests, all pass after that version update. `flutter analyze` on the touched files: no new issues.

## Phone tests (225) - router OFF, Extended RAM OFF
1. **Router echo first:** both phones on the router, call → "Calling…" → rings in ~3 s (unchanged).
2. **Wi-Fi Direct comeback:** phones apart (no link), open Ali's chat, call → "Waiting for Ali to connect…". Walk Ali's phone into range with its app open. Note the seconds until "Ringing…" (aim 15-35 s). Logs: `CALL_NEARBY_WAIT start`, `WD_FRIEND ... call_open` or `call_join`, `CALL_NEARBY_WAIT end why=route` or `rang`.
3. **Ali's app closed:** same as 2, Ali's screen off → may still be slow (Ali's own search timer); 226 fixes this.
4. **Mesh A↔B↔C:** A calls C through B → "Calling…" (never "Waiting for…"), rings as today, no group change on A.
5. **Never comes back:** call, keep Ali away → after 60 s "Couldn't reach them — try again"; no ghost ring later on Ali's phone.
6. **Cancel while waiting:** end the call during "Waiting for…" → logs `CALL_NEARBY_WAIT end why=ended` and `call_wait end why=call_side`.
7. **Live call:** during a connected call, Nearby groups do not move (same as before).

Send logs from both phones for tests 2, 4 and 5.
