# APPLY app 3.0.85+156: bundles 272-276

Zip: `locallink_app_3.0.85_2026-11-14.zip`, on top of `6bf30bd` (3.0.84+155 + bundle 271).
**Deploy the backend 272-276 FIRST** (`APPLY_backend_272-276.md`). The app works with the old
server too (the map shows "Server off - your links only" style data), but live data needs it.

## What changed
- **272 admin map (option B):** while the server is connected, the app admin map = your links +
  the server's live map (`GET /api/v1/admin/link-map`); server lines are blue (`0xFF3B82C4`
  everywhere); server off = "Server off - your links only". Full screen gets the same lines.
- **273 My links:** small map at the top of Chats - only your contacts (offline grey), a relay
  that is not a contact is the LinkUp logo (no name, "+N" for more phones). Tap = full map,
  tap a person = chat. Settings > Privacy > "Show My links map" (on by default).
- **274 live admin:** the server's `admin_link_map_changed` hint makes the app admin panel,
  dashboard and network page re-read quietly (max once a second; 60 s poll as fallback).
  Dashboard "Live network": each phone once (Server / Local Wi-Fi only / Wi-Fi Direct only /
  Mesh only / Offline) in the map colours; the row counts links.
- **275 quiet update:** the older phone gets ONE popup "New LinkUp found nearby - Getting it..."
  that starts by itself (no list, no names), downloads inside LinkUp, checks size + package,
  then Install opens Android's own update screen. Android asks once "Allow from this source".
  The phone with the new app shows nothing; it shares only on the same Wi-Fi / Wi-Fi Direct,
  battery >= 30 % or charging, not in a call, one at a time. APK deleted by itself (first start
  of the new version, cancel/fail, older than 24 h). Old Ask list + "Share / Not now" dialog gone.
- **276 names:** "My Android Phone (...)", "My LinkUp phone", "Phone", "LinkUp user" are never a
  person's name: display name -> username without @ -> "LinkUp user"; phone = "<name>'s phone".

## Android
New permission `REQUEST_INSTALL_PACKAGES` + FileProvider `${applicationId}.update275`
(only `<cache>/update275/`). Native: `UpdateInstall275.kt`, `UpdateFileProvider275.kt`,
5 methods on the `locallink/app_share` channel.

## Old tests changed (listed)
- `bundle213e_test.dart` rewritten for the quiet sharer (11 tests).
- `bundle213f_test.dart:128` `SilentUpdate275.showPopup = `.
- `link_paths_zoom_222_test.dart:100` new map lock hash (272 map change).
- `bundle210f_screen_test.dart:45` permission count 25 -> 26 (275 install permission;
  NOT in the TODO list - needed by the install the user chose).
- Version lines: `bundle223_logs_test.dart`, `nearby_190_test.dart`.

## Checks here
- `flutter test` all 281 files in 12 chunks: 2737 passed, 0 failed (2711 + 26 new).
  One run of `bundle210a_server_test` "4th phone 503" hit "Connection reset by peer" under load;
  passed 4 re-runs, file not touched.
- `flutter analyze`: 176 issues, 0 errors (same as before).
- Release APK: `flutter build apk --release --dart-define=LOCLINK_ALLOW_INSECURE_HTTP=true` -> BUILD_EXIT=0,
  109.7 MB; aapt2: `com.sajjad.linkup` versionCode 156 / 3.0.85, REQUEST_INSTALL_PACKAGES,
  provider `com.sajjad.linkup.update275`.

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_3.0.85_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_272.md docs/history/TODO_273.md docs/history/TODO_274.md docs/history/TODO_275.md docs/history/TODO_276.md docs/history/APPLY_app_3.0.85.md docs/history/LinkUp_mock_275_silent_update.html
git commit -m "v3 3.0.85 bundles 272-276: admin map shows the server live map while connected (blue server lines, Server off - your links only), My links card on Chats (contacts only, relay = LinkUp logo, Settings switch), live admin refresh on admin_link_map_changed + dashboard counts each phone once in map colours, quiet nearby update (auto popup, no names, in-app download + Android installer, APK auto delete, sharer silent rules), never show default phone names as a person (username without @, <name>'s phone)"
git push
```
Then GitHub > LocalLink > Actions > App CI should be green. Install the new APK over the old app.

## Phone checks
1. Admin phone, server on: Admin > map shows other online phones + blue lines; turn server off
   -> "Server off - your links only".
2. Chats: My links card at the top; offline contacts grey; Settings switch hides it.
3. Web + app admin dashboard: colours differ per slice, Phones = number of phones.
4. Old app (3.0.84) next to a 3.0.85 phone on the same Wi-Fi: popup comes by itself, download,
   Install -> Android asks once -> update. After the update: toast "LinkUp updated to 3.0.85".
5. No "My Android Phone (...)" anywhere (web People/Devices, app admin, chats).
