# APPLY app 3.0.94+165 (TODO 296 = H: every map shows only true, live data)

Zip: `locallink_app_296_2026-11-14.zip`, on top of GitHub `0f818ae` (3.0.93+164).
Backend 296 (`locallink_backend_296_2026-11-14.zip`) goes FIRST. With an old server the app
notices the unknown frame and stops sending it (nothing breaks).

## What changes
- H1 (direct link proof): a Wi-Fi / Wi-Fi Direct link counts on the maps only while our own ping got
  its answer in the last 10 s (or a file is coming in on it). The 15 s rule that closes a link, the
  route choice and sending do not change.
- H2 (far friends): only while LinkUp is open on screen, every 10 s a tiny locked "are you there"
  goes to each friend reached through other phones. Their phone answers at once.
  - Friend in colour only with an answer (or any packet from them) in the last 15 s.
  - "via" on the card = the phone the answer really came through.
  - Background: nothing extra is sent; the old path rule is used.
  - A friend with an older LinkUp never answers: the old rule stays for them (no false grey).
  - Friends only, locked only. About 300 bytes per far friend per 10 s.
- H3: the 20 s grace is gone. Lost proof = grey (or Online) at once; no "Connecting…" for a lost way.
  The G1 call check (295) uses the same mark.
- H4 (admin maps): the app sends only proven links (no more "seen in 4 min") in a new
  `link_report_296` frame: at once on a change (2 s wait to group changes) and every 15 s while on
  the server (checked every 5 s on screen, every 15 s in the background).
  `presence_update` still carries the links for old servers.

## Files
Dart: `presence_hub.dart`, `switch_rules.dart` (`connectingMax` 0), `reach_check_296.dart` (new),
`presence_service.dart`, `local_route_policy_service.dart` (proof list, maps only),
`local_link_app.dart` (foreground + proof wiring), version files.
Kotlin: `LocalLinkTransportService.kt` (`proven`, `last_pong_at` per peer in the topology),
`mesh/LinkProof296.kt` (new).
Tests: new `test/map_truth_296_test.dart` (16), Kotlin `LinkProof296Test` (4).
Old tests changed (rule changed on purpose by H3): `nearby_158_test` "path gone: Nearby for 20 s"
-> "Offline at once"; `link_201_test` "grace = Connecting" -> "Offline / Online at once";
version lines in `bundle223_logs_test` / `nearby_190_test`. Nothing removed.

## Tests (here)
- `flutter analyze`: 0 errors; no new warnings or infos in changed files.
- Full Flutter suite: 299 files, 12 chunks, 2912 tests, all passed. One chunk first failed in
  `bundle210a_server_test` (old flaky 503 / 416 timing test); it passes alone and on the re-run of the
  whole chunk.
- Kotlin: compile clean; all JVM unit tests 499/499 OK (new `LinkProof296Test` 4).
- Backend 296: `go test ./...` 6 packages ok.
- NOT checked here: real phones, radios, the live web map. Release APK: CI builds it.

## Phone check
1. Server 296 first, then 3.0.94 on all phones.
2. 3 phones A - B - C (C only through B). LinkUp open on A. Turn off B's Wi-Fi:
   A greys C within ~15 s; the web map drops the line within ~20 s. B back: C in colour after the
   first answer (~10 s).
3. Walk away with a phone: its line goes within ~15 s (app) / ~20 s (web).
4. Leave all phones still for 10 min: no flicker on the card or the web map.
5. A friend with the old 3.0.93 through mesh: stays as before (not grey by mistake).

## Commands
```powershell
cd "C:\Users\sajjad Ahmed\Downloads\LocalLink"
git pull
Expand-Archive -Force "$env:USERPROFILE\Downloads\locallink_app_296_2026-11-14.zip" .
git add -A
git add -f docs/history/TODO_296.md docs/history/APPLY_app_296.md
git commit -m "v3.0.94+165: maps show only true live data (direct links only while proven, far friends checked every 10 s while open with the real via, no 20 s grace, only proven links sent to the server at once and every 15 s)"
git push
```
