# APPLY 223 - clock heal, join key from one phone, smooth start, offline quiet, share step 2, Wi-Fi Direct name tags, clean logs (app 3.0.63+134 + backend)

**Order (after 222):**
1. **Backend 223 zip**: commit, run `go test ./...`, deploy. No migration.
2. **App 223 zip**: commit, then build the APK. No database change.

Phones on build 133 keep working with phones on 134. Old phones simply don't send the new name tag, and their full tag is read as before.

## PowerShell

Backend:
```
cd "C:\Users\sajjad Ahmed\Downloads\localLinkBackend"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_backend_223_2026-11-06.zip" -DestinationPath .
go test ./...
git add -A
git commit -m "v3 bundle 223 backend: heal rate-limit windows and login locks written while the clock was ahead"
git push
```

App:
```
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
Expand-Archive -Force -Path "C:\Users\sajjad Ahmed\Downloads\locallink_app_223_2026-11-06.zip" -DestinationPath .
flutter pub get
flutter test
git add -A
git commit -m "v3 3.0.63+134 bundle 223: join key from one phone, WS retry limit, one permission at a time, password lock off the screen thread, quiet offline, share step 2 always usable, Wi-Fi Direct name tags, clean logs"
git push
```

## What users see
- **First start (ZTE):** the permission pop-ups come one after another. None is lost any more (one was dropped at 07:47:36).
- **Sign in:** no 6 s freeze. The password lock runs off the screen thread.
- **No Wi-Fi / server down:** a chat opens at once with the saved messages (it was a 13 s shimmer). No background calls are made to an unreachable server.
- **Server back:** the socket is back within about 15 s. Each try waits at most 10 s (it could hang 65 s).
- **Share app:**
  - The download QR (step 2, and the same-Wi-Fi screen) has the yellow note "Scan with the camera app, not the Wi-Fi scanner" (mock `mock_223_qr_text.png`). Step 1 keeps its Wi-Fi scanner text.
  - Step 2 never shows an empty "Tap the one…" (mock `mock_223_step2.png`). It shows a spinner "Getting the download address..." for up to 10 s (the QR appears by itself), then all addresses + "Try again" + the Gateway tip.
- **Nearby (Wi-Fi Direct):** a phone whose full tag never arrives is still seen by its short name tag (`LinkUp-<8 chars>-<flags>`). The app then asks that phone exactly for its full tag.
- **Her account made offline:** her phone takes the server's join key from ONE nearby phone when the server's signature checks. The server's own key always replaces it later.

## How it works (short)
- **A (backend):** a rate-limit window or login lock with a start time in the future (clock was ahead) is reset instead of blocking. Cleanup also deletes future rows.
- **B:** `JOIN_KEY_FROM_PHONE n=1` / `JOIN_KEY_REPLACED_BY_SERVER`; a key change remakes her join box.
- **C/H:** socket `ready` / `done` errors are caught (no `uncaught_async_error`). `WS_RETRY_TIMEOUT` after 10 s; network back = redial.
- **I:** one native permission queue: `PERM_ASK` / `PERM_ANSWER` / `PERM_QUEUED`. The reply goes to Dart only after the answer (60 s limit).
- **J:** `PasswordKdf.deriveAsync` / `verifyAsync` run on a background isolate.
- **K:** the LAN beacon pauses 15 s after "Network is unreachable" (`LAN_BEACON paused/resumed`).
- **L/M/N:** a new `ServerReach` gate. `SERVER_CALL_SKIPPED what=.. why=no_network|server_down|no_server`, once per reason. A connected socket always goes ahead (hotspot host).
- **E:** wlan0 is accepted when it is new, or when it is a `.1` address with no router. `ip_wait` / `ip_none` / `ip_picked` lines are logged.
- **F:**
  - The service is published with the name `LinkUp-<id8>-<flags>`; the service type `_locallink._tcp` is unchanged and "LocalLink" names are still read.
  - A PTR with no TXT within 2 s leads to ONE exact TXT ask (`WD_TAG txt_ask`).
  - Name tags (`WD_TAG from_name`) fill the nearby list and Pair. They can't do a silent group join, because the group password is only in the full tag.
- **O:**
  - The stamp comes from the version (`APP_BUILD_STAMP v3 · 3.0.63+134`, INFO).
  - PAIR_* lines are INFO.
  - SKIPPED lines are written once per state, and `DIRECT_TRANSPORT_INFO` only on change.
  - `ACCOUNT_OFFLINE_BOX reason=phone_only|no_network|server_down`.
  - Offline failures are WARN `offline=<type>`.

## Files
See `TODO_223.md` -> Files: every file, and which ones were outside the first list.

**Old tests changed (expectation only):**
- `test/join_carrier_222_test.dart`: 1 expectation -> `isNotNull` (B: one phone is now enough, which is what you chose).
- `android/.../Call189Test.kt`: 3 -> 5. It has been failing since 205, which added 2 more `lastGroupChangeAt` lines (Q5).
- `test/nearby_190_test.dart`: version line -> `3.0.63+134`, and the stamp check -> `AppBuild.stamp` (as in every bundle).

## Found while fixing
Q1-Q22 in `TODO_223.md` -> section Q. Each one has its own test.

## Tests run here
All run here in the sandbox on 2026-11-06 (Flutter 3.47.7, Go 1.27.3, Kotlin 2.0.21 on JRE 21):
- **Flutter, full suite:** 2239 passed, 0 failed (234 test files, run in 11 chunks).
- **New Dart tests (54):**
  - `bundle223_join` 6, `bundle223_ws` 6, `bundle223_share` 10;
  - `bundle223_first_start` 9, `bundle223_offline` 11;
  - `bundle223_nearby` 5, `bundle223_logs` 7.
- **Kotlin JVM tests:** 381 OK. New: `Perm223Test` 7, `Share223Test` 6, `mesh/LanBeacon223Test` 5, `mesh/Tag223Test` 5. The old `Call189Test` passes again (Q5).
- **Backend:** `go vet ./...` is clean and `go test ./...` passes. New: `clock_heal_223_test.go`, 6 tests (223-s1..s6).
- **dart analyze lib:** 125 issues, the same as 222. All are old infos; none is new.
- **Negative checks:** with each fix taken out again, its tests fail:
  - A: 5 fail;
  - L/M: 5 fail;
  - E (wlan0): 2 fail;
  - C/H: checked too.
- **Not tested here:** real phones. Wi-Fi Direct, the permission pop-ups, the hotspot and the isolate speed on the ZTE can only be checked by the phone tests below.

## Phone tests
See `TODO_223.md` -> Phone tests (223-A ... 223-O).

Logs to send if something fails:
- Join: `JOIN_KEY_FROM_PHONE`, `JOIN_KEY_REPLACED_BY_SERVER`, `JOIN_BOX_MADE`, `JOIN_RELAY_*`.
- Socket: `WS_RETRY_TIMEOUT`, `WS_STREAM_ERROR`, `WS_READY_TIMEOUT`.
- Permissions: `PERM_ASK`, `PERM_ANSWER`, `PERM_QUEUED`.
- Offline: `SERVER_CALL_SKIPPED`, `LAN_BEACON`.
- Share: `SHARE_APP ip_wait / ip_none / ip_picked`, and the Android line `SHARE_APP addr ms= found= list=`.
- Nearby: `WD_TAG from_name`, `WD_TAG txt_ask`, `WD_TAG_FAIL`, and the window end line `WD_SEARCH end ... names=`.

## Honest limits
- A name tag only says WHICH phone it is. A silent join still needs the full tag (password). The exact TXT ask may fix that on the Realme / ZTE; the phone test (223-F) will tell.
- The rename confirm in `home_screen.dart` still checks the password on the screen thread (rare; left as is).
- Section P (the `LINK_AUTH peer_has=` line) is a watch item for the next logs; it is not in 223.
